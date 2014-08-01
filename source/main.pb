EnableExplicit

XIncludeFile "WindowMain.pbf"
XIncludeFile "WindowTranscode.pbf"
XIncludeFile "data.pbi"

#DEBUG_GUI = #True
#DEBUG_FFMPEG = #False

#GUI_UPDATE = 100

Enumeration 
  #STATE_WAITING
  #STATE_DONE
  #STATE_ERROR
  #STATE_ABORT
  #STATE_ACTIVE
EndEnumeration

Global Event
Global dirP$, dirC$

Structure file
  source$
  destination$
EndStructure

Structure job
  state.i     ; waiting / done / error ...
  startTime.i ; UNIX timestamp of beginning transcoding
  endTime.i   ; UNIX timestamp of finishing transcoding
  
  file.file
  error$
  durationTotal$  ; duration string as returned by FFMPEG
  durationCurrent$
  durationSecondsTotal.i  ; duration calculated as seconds
  durationSecondsCurrent.i
  percent.i
EndStructure

Global Queue.b                ; #True if next job should be startet, #False if next job should NOT be startet
Global CurrentJobAbort.b      ; global variable for thread, set to #True if transcoding should be aborted
Global CurrentJobFFMPEG       ; stores program ID of ffmpeg
Global *CurrentJob.job        ; pointer to current job in list()
Global NewList  jobs.job()   ; list of all jobs
Global mutexJobs = CreateMutex()

Global FileLogGUI, FileLogFFMPEG

Global ImageStart, ImageStop, ImageNew, ImageDelete, ImageEdit, ImageUp, ImageDown, ImageRequeue

Declare startNextJob()
Declare SizeCallback(WindowID, Message, wParam, lParam)
Declare loadWindowMainImages()
Declare updateQueueGadget(saveSelected = #False)
Declare LogGUI(logEntry$)
Declare LogFFMPEG(logEntry$)

Procedure explodeStringArray(Array a$(1), s$, delimeter$)
  Protected count, i
  count = CountString(s$,delimeter$) + 1
  
  Debug Str(count) + " substrings found"
  ReDim a$(count)
  For i = 1 To count
    a$(i - 1) = StringField(s$,i,delimeter$)
  Next
  ProcedureReturn count ;return count of substrings
EndProcedure

Procedure loadJobs()
  LogGUI("loading list of jobs...")
  Protected  i, size
  
  If OpenPreferences("jobs.ini")
    
    LockMutex(mutexJobs)
    
    ClearList(jobs())
    size = ReadPreferenceInteger("jobcount", 0)
    If size > 0
      For i = 0 To size-1 Step 1
        AddElement(jobs())
        With jobs()
          PreferenceGroup("job"+Str(i))
          \state = ReadPreferenceInteger("state", #STATE_WAITING)
          \startTime = ReadPreferenceInteger("start", 0)
          \endTime = ReadPreferenceInteger("end", 0)
          \file\source$ = ReadPreferenceString("source", "")
          \file\destination$ = ReadPreferenceString("destination", "")
          \error$ = ReadPreferenceString("error", "")
          \durationTotal$ = ReadPreferenceString("duration", "00:00:00")
        EndWith
      Next
    EndIf
    ForEach jobs()
      If jobs()\file\source$ = ""
        DeleteElement(jobs(), 1)
      EndIf
    Next
    
    UnlockMutex(mutexJobs)
    
    ClosePreferences()
    updateQueueGadget()
  Else
    LogGUI("error: could not open jobs.ini")
  EndIf 
EndProcedure

Procedure saveJobs()
  LogGUI("saving list of jobs...")
  Protected  i, size
  
  If CreatePreferences("jobs.ini")
    LockMutex(mutexJobs)
    
    ResetList(jobs())
    size = ListSize(jobs())
    WritePreferenceInteger("jobcount", size)
    For i = 0 To size-1 Step 1
      SelectElement(jobs(), i)
      PreferenceGroup("job"+Str(i))
      WritePreferenceInteger("state", jobs()\state)
      WritePreferenceInteger("start", jobs()\startTime)
      WritePreferenceInteger("end", jobs()\endTime)
      WritePreferenceString("source", jobs()\file\source$)
      WritePreferenceString("destination", jobs()\file\destination$)
      WritePreferenceString("error", jobs()\error$)
      WritePreferenceString("duration", jobs()\durationTotal$)
    Next
    
    UnlockMutex(mutexJobs)
    ClosePreferences()
  Else
    LogGUI("error: could not create jobs.ini")
  EndIf 
EndProcedure

Procedure init()
  dirP$ = ProgramFilename()
  dirC$ = GetCurrentDirectory()
  
  FileLogFFMPEG = CreateFile(#PB_Any, "ffmpeg.log")
  FileLogGUI = CreateFile(#PB_Any, "gui.log")
  
  OpenWindowMain()
  OpenWindowTranscode()
  
  SetWindowCallback(@SizeCallback(), WindowMain)
  loadWindowMainImages()
  
  AddGadgetColumn(GadgetQueue, 1, "source path", 150)
  AddGadgetColumn(GadgetQueue, 2, "destination path", 150)
  AddGadgetColumn(GadgetQueue, 3, "state", 80)
  
  EnableGadgetDrop(GadgetQueue, #PB_Drop_Files, #PB_Drag_Copy|#PB_Drag_Move|#PB_Drag_Link)
  
  loadJobs()
  
  HideWindow(WindowMain, #False)
EndProcedure

Procedure exit()
  HideWindow(WindowMain, #True)
  
  saveJobs()
  
  CloseFile(FileLogFFMPEG)
  CloseFile(FileLogGUI)
  End
EndProcedure

Procedure LogGUI(logEntry$)
  CompilerIf #DEBUG_GUI
    Debug "GUI: "+logEntry$
  CompilerEndIf
  
  If IsFile(FileLogGUI)
    logEntry$ = FormatDate("%hh:%ii:%ss - ",Date()) + logEntry$
    WriteStringN(FileLogGUI, logEntry$)
  EndIf
EndProcedure

Procedure LogFFMPEG(logEntry$)
  CompilerIf #DEBUG_FFMPEG
    Debug "FFMPEG: "+logEntry$
  CompilerEndIf
  
  If IsFile(FileLogFFMPEG)
    logEntry$ = FormatDate("%hh:%ii:%ss - ",Date()) + logEntry$
    WriteStringN(FileLogFFMPEG, logEntry$)
  EndIf
EndProcedure

Procedure getSeconds(time$)
  time$ = Trim(time$)
  
  ProcedureReturn ParseDate("%hh:%ii:%ss", time$)
  
;   Protected h, m, s, c1, c2
;   
;   c1 = FindString(time$, ":", 1)
;   c2 = FindString(time$, ":", c1+1)
;   h = Val(Mid(time$, 1, c1-1))
;   m = Val(Mid(time$, c1+1, c2-c1-1))
;   s = Val(Mid(time$, c2+1))
;   
;   ProcedureReturn s + 60*(m + 60*h)
EndProcedure

Procedure ffmpeg(*job.job)
  Protected prog
  Protected c$ = ""
  
  c$ = c$ + "-i "+#DQUOTE$+*job\file\source$+#DQUOTE$
  c$ = c$ + " -map 0"
  c$ = c$ + " -scodec copy"
  c$ = c$ + " -acodec libvorbis"
  c$ = c$ + " -aq 2"
  c$ = c$ + " -vcodec libx264"
  c$ = c$ + " -crf 21"
;   c$ = c$ + " -vf scale=-1:720"
  c$ = c$ + " -preset slow"
  c$ = c$ + " -tune film"
  c$ = c$ + " -profile:v high"
  c$ = c$ + " -threads 4"
  c$ = c$ + " "+#DQUOTE$+*job\file\destination$+#DQUOTE$
  Debug dirC$+"ffmpeg"
  Debug c$
  prog = RunProgram(dirC$+"ffmpeg", c$, "./", #PB_Program_Open|#PB_Program_Read|#PB_Program_Error|#PB_Program_Write|#PB_Program_Hide)
  If Not prog
    LogGUI("Could not start '"+dirC$+"ffmpeg'")
    ProcedureReturn
  EndIf
  
  Protected totalTime, percent
  Protected out$, sec$
  
  *CurrentJob\startTime = Date()
  *job\durationTotal$ = "00:00:00"
  *job\durationCurrent$ = "00:00:00"
  *job\percent = 0
  *job\state = #STATE_ACTIVE
  updateQueueGadget(#True)
  
  Repeat
    Delay(1)
    
    If Not IsProgram(prog)
      Break
    EndIf
    If Not ProgramRunning(prog)
      Break
    EndIf
    If CurrentJobAbort
      CurrentJobAbort = #False
      Break
    EndIf
    
    out$ = ReadProgramError(prog)
    If out$
      LogFFMPEG(out$)
      
      If FindString(out$, "Duration:") ; found total duration of clip
        out$ = RemoveString(out$, "Duration:")
        out$ = Trim(Left(out$, FindString(out$, ".")-1))
        *job\durationTotal$ = out$
        *job\durationSecondsTotal= getSeconds(out$)
      EndIf
      
      If FindString(out$, "frame=")
        sec$ = out$
        sec$ = Mid(sec$, FindString(sec$, "time=") + 5)
        sec$ = Left(sec$, FindString(sec$, ".")-1)
        *job\durationCurrent$ = sec$
        *job\durationSecondsCurrent= getSeconds(sec$)
        
        If *CurrentJob\durationSecondsTotal > 0
          percent = 100 * *job\durationSecondsCurrent / *job\durationSecondsTotal
          If percent <> *job\percent
            *job\percent = percent
;             LogGUI(*job\durationCurrent$ + " / " + *job\durationTotal$ + " - " + Str(percent) + "%")
          EndIf
        EndIf
      EndIf
      
    EndIf
    If AvailableProgramOutput(prog)
      out$ = ReadProgramString(prog)
      If out$
        LogFFMPEG(out$)
      EndIf
    EndIf
  ForEver
  If IsProgram(prog)  ; if ffmpeg is still running
    If ProgramRunning(prog)
      LogGUI("kill ffmpeg")
      KillProgram(prog)
    EndIf 
  EndIf
  ; Close read connection with ffmpeg
  CloseProgram(prog)
  
  ; save finish date
  *job\endTime = Date()
  If *job\durationSecondsCurrent = *job\durationSecondsTotal
    *job\state = #STATE_DONE
  Else
    *job\state = #STATE_ABORT
  EndIf
  updateQueueGadget(#True)
  
  ; wait a moment for updating the transcoding window
  Delay(2 * #GUI_UPDATE)
  ; no current job
  *CurrentJob = 0
  HideWindow(WindowTranscode, #True)
  LogGUI("ffmpeg thread finished")
EndProcedure

Procedure SizeCallback(WindowID, Message, wParam, lParam)
  Protected *SizeTracking.MINMAXINFO
  ; Here is the trick. The GETMINMAXINFO must be processed
  ; and filled with min/max values...
  If Message = #WM_GETMINMAXINFO
    *SizeTracking = lParam
    *SizeTracking\ptMinTrackSize\x = 640
    *SizeTracking\ptMinTrackSize\y = 480
    *SizeTracking\ptMaxTrackSize\x = 999999;7680
    *SizeTracking\ptMaxTrackSize\y = 4320
  EndIf
  
  ProcedureReturn #PB_ProcessPureBasicEvents
EndProcedure

Procedure SetGadgetImage(Gadget, Image)
  ResizeImage(Image, GadgetWidth(Gadget)-10, GadgetHeight(Gadget)-10)
  SetGadgetAttribute(Gadget, #PB_Button_Image, ImageID(Image))
EndProcedure

Procedure loadWindowMainImages()
  UsePNGImageDecoder()
  
  ImageStart  = CatchImage(#PB_Any, ?DataImageStart)
  ImageStop   = CatchImage(#PB_Any, ?DataImageStop)
  ImageNew    = CatchImage(#PB_Any, ?DataImageNew)
  ImageDelete = CatchImage(#PB_Any, ?DataImageDelete)
  ImageEdit   = CatchImage(#PB_Any, ?DataImageEdit)
  ImageUp     = CatchImage(#PB_Any, ?DataImageUp)
  ImageDown   = CatchImage(#PB_Any, ?DataImageDown)
  ImageRequeue= CatchImage(#PB_Any, ?DataImageRequeue)
  
  SetGadgetImage(ButtonStartStop, ImageStart)
  SetGadgetImage(ButtonNew, ImageNew)
  SetGadgetImage(ButtonDelete, ImageDelete)
  SetGadgetImage(ButtonEdit, ImageEdit)
  SetGadgetImage(ButtonUp, ImageUp)
  SetGadgetImage(ButtonDown, ImageDown)
  SetGadgetImage(ButtonRequeue, ImageRequeue)
  
EndProcedure

Procedure GadgetQueue(EventType)
  
EndProcedure

Procedure FileDrop()
  Protected files$, i
  Protected Dim files$(0)
  files$ = EventDropFiles()
  
  If files$
    explodeStringArray(files$(), files$, Chr(10))
    For i = 0 To ArraySize(files$())-1
      Debug "- "+files$(i)
    Next
    
  EndIf
  
EndProcedure

Procedure ButtonStartStop(EventType)
  If Queue
    LogGUI("button: stop queue")
    Queue = #False
  Else
    LogGUI("button: start queue")
    Queue = #True 
  EndIf
  
EndProcedure

Procedure ButtonNew(EventType)
  
EndProcedure

Procedure ButtonEdit(EventType)
  
EndProcedure

Procedure ButtonDelete(EventType)
  Protected i
  LockMutex(mutexJobs)
  If ListSize(jobs()) > 0
    If GetGadgetState(GadgetQueue) > -1
      For i = ListSize(jobs()) -1 To 0 Step -1
        If GetGadgetItemState(GadgetQueue, i)
          SelectElement(jobs(), i)
          DeleteElement(jobs(), 1)
        EndIf
      Next
    EndIf
  EndIf
  UnlockMutex(mutexJobs)
  updateQueueGadget()
EndProcedure

Procedure ButtonUp(EventType)
  Protected count, i
  Protected NewList selectedItems()
  count = ListSize(jobs())
  
  If count > 1 ; need at least 2 elements to swap
    If GetGadgetState(GadgetQueue) > -1
      ; something is selected!
      LockMutex(mutexJobs)
      ; lock mutex in order to work on job list
      For i = 1 To count - 1 Step 1
        ; iterate through list from top to bottom
        ; move all selected items up by one
        If GetGadgetItemState(GadgetQueue, i) &  #PB_ListIcon_Selected
          ; this item is selected -> swap with following item
          SwapElements(jobs(), SelectElement(jobs(), i), SelectElement(jobs(), i-1))
          ; save all previously selected items
          AddElement(selectedItems())
          selectedItems() = i-1
        EndIf
      Next
      UnlockMutex(mutexJobs)
      updateQueueGadget()
      ForEach selectedItems()
        SetGadgetItemState(GadgetQueue, selectedItems(), #PB_ListIcon_Selected)
      Next
      ClearList(selectedItems())
    EndIf
  EndIf
EndProcedure

Procedure ButtonDown(EventType) 
  Protected count, i
  Protected NewList selectedItems()
  count = ListSize(jobs())
  
  If count > 1 ; need at least 2 elements to swap
    If GetGadgetState(GadgetQueue) > -1
      ; something is selected!
      LockMutex(mutexJobs)
      ; lock mutex in order to work on job list
      For i = count - 2 To 0 Step -1
        ; iterate through list from bottom to top
        ; move all selected items down by one
        If GetGadgetItemState(GadgetQueue, i) &  #PB_ListIcon_Selected
          ; this item is selected -> swap with following item
          SwapElements(jobs(), SelectElement(jobs(), i), SelectElement(jobs(), i+1))
          ; save all previously selected items
          AddElement(selectedItems())
          selectedItems() = i+1
        EndIf
      Next
      UnlockMutex(mutexJobs)
      updateQueueGadget()
      ForEach selectedItems()
        SetGadgetItemState(GadgetQueue, selectedItems(), #PB_ListIcon_Selected)
      Next
      ClearList(selectedItems())
    EndIf
  EndIf
;   Protected selected, count
;   
;   selected = GetGadgetState(GadgetQueue)
;   Debug "selected = " +Str(selected)
;   If selected > -1
;     ; first element: 0
;     LockMutex(mutexJobs)
;     count = ListSize(jobs())
;     Debug "count = "+Str(count)
;     If selected < count -1
;       SwapElements(jobs(), SelectElement(jobs(), selected), SelectElement(jobs(), selected +1))
;       UnlockMutex(mutexJobs)
;       updateQueueGadget()
;       SetGadgetState(GadgetQueue, selected +1)
;     Else
;       UnlockMutex(mutexJobs)
;     EndIf
;   EndIf
EndProcedure

Procedure ButtonRequeue(EventType) 
  Protected i
  LockMutex(mutexJobs)
  If ListSize(jobs()) > 0
    If GetGadgetState(GadgetQueue) > -1
      For i = 0 To ListSize(jobs()) -1
        If GetGadgetItemState(GadgetQueue, i)
          SelectElement(jobs(), i)
          jobs()\state = #STATE_WAITING
          jobs()\error$ = ""
        EndIf
      Next
    EndIf
  EndIf
  UnlockMutex(mutexJobs)
  updateQueueGadget(#True)
EndProcedure

Procedure updateGadgets()
  Static lastUpdate = 0
  Protected elapsedTime, totalTime, remainingTime  
  Static lastQueue
  
  If lastUpdate < ElapsedMilliseconds() - #GUI_UPDATE
    lastUpdate = ElapsedMilliseconds()
    
    If *CurrentJob
      elapsedTime = Date() - *CurrentJob\startTime
      If *CurrentJob\percent
        totalTime = elapsedTime * 100 / *CurrentJob\percent
        remainingTime = totalTime - elapsedTime
      Else
        totalTime = 0
        remainingTime = 0
      EndIf

      SetGadgetText(StringPosition, *CurrentJob\durationCurrent$+" / "+*CurrentJob\durationTotal$)
      SetGadgetText(StringFrames, "0 / 0")
      SetGadgetText(StringTimeElapsed, FormatDate("%hh:%ii:%ss", elapsedTime))
      SetGadgetText(StringTimeRemaining, FormatDate("%hh:%ii:%ss", remainingTime))
      SetGadgetState(ProgressBarVideo, *CurrentJob\percent)
    EndIf
    
    If Queue <> lastQueue
      lastQueue = Queue
      If Queue 
        SetGadgetImage(ButtonStartStop, ImageStop)
      Else
        SetGadgetImage(ButtonStartStop, ImageStart)
      EndIf
    EndIf
    
    If Queue And Not *CurrentJob ; if queue is running but no current job is active
      If Not startNextJob()
        ; no more undone jobs available or some other error
        Queue = #False
      EndIf
    EndIf
    
    If GetGadgetState(GadgetQueue) > -1
      ; only enable some GUI elements if a job is selected
      If GetGadgetItemState(GadgetQueue, 0) & #PB_ListIcon_Selected
        DisableGadget(ButtonUp, #True)
      Else
        DisableGadget(ButtonUp, #False)
      EndIf
      If GetGadgetItemState(GadgetQueue, ListSize(jobs())-1) & #PB_ListIcon_Selected
        DisableGadget(ButtonDown, #True)
      Else
        DisableGadget(ButtonDown, #False)
      EndIf
      DisableGadget(ButtonRequeue, #False)
      DisableGadget(ButtonEdit, #False)
      DisableGadget(ButtonDelete, #False)
    Else
      DisableGadget(ButtonRequeue, #True)
      DisableGadget(ButtonUp, #True)
      DisableGadget(ButtonDown, #True)
      DisableGadget(ButtonEdit, #True)
      DisableGadget(ButtonDelete, #True)
    EndIf
    
    
  EndIf
EndProcedure

Procedure startNextJob()
  ; lock mutex before testing for *CurrentJob and release after setting it!
  LockMutex(mutexJobs)
  If *CurrentJob
    ; there is some other jobstill running!
    UnlockMutex(mutexJobs) ; don't forget to unlock mutex here!
    ProcedureReturn #False
  EndIf
  
  ForEach jobs()
    ; search for a job waiting to be processed
    If jobs()\state = #STATE_WAITING
      *CurrentJob = jobs() ; copy pointer to this element
      *CurrentJob\state = #STATE_ACTIVE
      Break ; leave loop
    EndIf
  Next
  UnlockMutex(mutexJobs)
  
  If Not *CurrentJob ; no next job found
    ProcedureReturn #False
  EndIf
  
  *CurrentJob\error$ = "" ; reset all past error messages
  ; check if source file exists
  If FileSize(*CurrentJob\file\source$) <= 0
    *CurrentJob\state = #STATE_ERROR
    *CurrentJob\error$ = "file not found"
    *CurrentJob = 0
    updateQueueGadget(#True)
    ProcedureReturn #True
  EndIf
  
  ; "reset" Transcoding window before showing
  SetGadgetText(StringInput, *CurrentJob\file\source$)
  SetGadgetText(StringOutput, *CurrentJob\file\destination$)
  SetGadgetText(StringPosition, "00:00:00 / 00:00:00")
  SetGadgetText(StringFrames, "0 / 0")
  SetGadgetText(StringTimeElapsed, "00:00:00")
  SetGadgetText(StringTimeRemaining, "00:00:00")
  SetGadgetState(ProgressBarVideo, 0)
  
  HideWindow(WindowTranscode, #False)
  
  CreateThread(@ffmpeg(), *CurrentJob)
  
  ProcedureReturn #True
EndProcedure

Procedure updateQueueGadget(saveSelected = #False)
  Protected text$, i
  Protected NewList selected()
  
  LockMutex(mutexJobs)
  If saveSelected
    For i = 0 To ListSize(jobs())-1
      If GetGadgetItemState(GadgetQueue, i) & #PB_ListIcon_Selected
        AddElement(selected())
        selected() = i
      EndIf
    Next
  EndIf
  ClearGadgetItems(GadgetQueue)
  ForEach jobs()
    text$ = GetFilePart(jobs()\file\source$) + Chr(10)
    text$ = text$ + GetPathPart(jobs()\file\source$) + Chr(10)
    text$ = text$ + GetPathPart(jobs()\file\destination$) + Chr(10)
    Select jobs()\state
      Case #STATE_WAITING
        text$ = text$ + "waiting"
      Case #STATE_ABORT
        text$ = text$ + "aborted"
      Case #STATE_ERROR
        text$ = text$ + "error"
      Case #STATE_DONE
        text$ = text$ + "done"
      Case #STATE_ACTIVE
        text$ = text$ + "transcoding"
      Default
        text$ = text$ + ""
    EndSelect
    AddGadgetItem(GadgetQueue, -1, text$)
  Next
  If saveSelected
    ForEach selected()
      SetGadgetItemState(GadgetQueue, selected(), #PB_ListIcon_Selected)
    Next
    ClearList(selected())
  EndIf
  UnlockMutex(mutexJobs)
EndProcedure

Procedure addJob(source$)
  LockMutex(mutexJobs)
  LastElement(jobs())
  AddElement(jobs())
  With jobs()
    \state = #STATE_WAITING
    \file\source$       = source$
    \file\destination$  = source$+".mkv"
    \durationTotal$ = ""
  EndWith
  UnlockMutex(mutexJobs)
  updateQueueGadget()
EndProcedure

init()

Repeat
  updateGadgets()
  Event = WaitWindowEvent(100)
  
  Select EventWindow()
    Case WindowMain
      If Not WindowMain_Events(Event)
        exit()
      EndIf
      If Event = #PB_Event_GadgetDrop Or Event = #PB_Event_WindowDrop
        FileDrop()
      EndIf
    Case WindowTranscode
      If Not WindowTranscode_Events(Event)
        If MessageRequester("Abort", "Do you really want to cancel transcoding?", #PB_MessageRequester_YesNo) = #PB_MessageRequester_Yes
          Queue = #False
          CurrentJobAbort = #True
        EndIf
      EndIf
  EndSelect
ForEver
End
; IDE Options = PureBasic 5.30 (Windows - x64)
; CursorPosition = 691
; FirstLine = 142
; Folding = aAAA+
; EnableXP