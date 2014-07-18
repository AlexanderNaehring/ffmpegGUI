EnableExplicit

XIncludeFile "WindowMain.pbf"
XIncludeFile "WindowTranscode.pbf"

#GUI_UPDATE = 100

Global Event
Global dirP$, dirC$

Structure file
  source$
  destination$
EndStructure

Structure job
  ID.i        ; Job id (for identification in queue)
  done.i      ; boolean
  startTime.i ; UNIX timestamp of beginning transcoding
  endTime.i   ; UNIX timestamp of finishing transcoding
  
  file.file
  framesTotal.i   ; number of frames as integer
  framesCurrent.i
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


Declare startNextJob()

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

Procedure init()
  ; search for ffmpeg binary
  dirP$ = ProgramFilename()
  dirC$ = GetCurrentDirectory()
  Debug dirP$
  Debug dirC$
EndProcedure

Procedure exit()
  HideWindow(WindowMain, #True)
  End
EndProcedure

Procedure addLog(logEntry$)
  Debug logEntry$
;   Protected text$
;   logEntry$ = logEntry$ + Chr(10)
;   logEntry$ = FormatDate("%hh:%ii:%ss - ",Date()) + logEntry$
;   
;   text$ = GetGadgetText(GadgetEditorLog)
;   text$ = logEntry$ + text$
;   SetGadgetText(GadgetEditorLog, text$)
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

  Debug c$
  prog = RunProgram(dirC$+"ffmpeg", c$, "./", #PB_Program_Open|#PB_Program_Read|#PB_Program_Error|#PB_Program_Write|#PB_Program_Hide)
  If Not prog
    Debug "Could not start '"+dirC$+"ffmpeg'"
    ProcedureReturn
  EndIf
  
  
  Protected totalTime
  Protected out$
  
  *CurrentJob\startTime = Date()
  *job\durationTotal$ = "00:00:00"
  *job\durationCurrent$ = "00:00:00"
  *job\percent = 0
  
  Repeat
    Delay(1)
    If Not IsProgram(prog)
      Break
    EndIf
    If Not ProgramRunning(prog)
      Break
    EndIf
    If CurrentJobAbort
      Break
    EndIf
    
    out$ = ReadProgramError(prog)
    If out$
      Debug out$
      
      If FindString(out$, "Duration:") ; found total duration of clip
        out$ = RemoveString(out$, "Duration:")
        out$ = Trim(Left(out$, FindString(out$, ".")-1))
        *job\durationTotal$ = out$
        *job\durationSecondsTotal= getSeconds(out$)
      EndIf
      
      If FindString(out$, "frame=")
        out$ = Mid(out$, FindString(out$, "time=") + 5)
        out$ = Left(out$, FindString(out$, ".")-1)
;         Debug Str(100*getSeconds(out$)/totalTime) + " %"
        *job\durationCurrent$ = out$
        *job\durationSecondsCurrent= getSeconds(out$)
        
        If *CurrentJob\durationSecondsTotal > 0
          Protected percent = 100 * *job\durationSecondsCurrent / *job\durationSecondsTotal
          If percent <> *job\percent
            Debug *job\durationCurrent$ + " / " + *job\durationTotal$ + " - " + Str(percent) + "%"
          EndIf
          *job\percent = percent
        EndIf
      EndIf
      
    EndIf
    If AvailableProgramOutput(prog)
      out$ = ReadProgramString(prog)
      If out$
        Debug out$
      EndIf
    EndIf
  ForEver
  If IsProgram(prog)  ; if ffmpeg is still running
    If ProgramRunning(prog)
      Debug "kill ffmpeg"
      KillProgram(prog)
    EndIf 
  EndIf
  ; Close read connection with ffmpeg
  CloseProgram(prog)
  
  ; save finish date
  *job\endTime = Date()
  If *job\durationSecondsCurrent = *job\durationSecondsTotal
    *job\done = #True
  EndIf
  
  ; wait a moment for updating the transcoding window
  Delay(2 * #GUI_UPDATE)
  ; no current job
  *CurrentJob = 0
  HideWindow(WindowTranscode, #True)
  Debug "ffmpeg thread finished"
  
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
  addLog("start/stop queue")
  
  If Queue
    Queue = #False
  Else
    Queue = #True 
    startNextJob()
  EndIf
  
EndProcedure

Procedure ButtonNew(EventType)
  
EndProcedure

Procedure ButtonEdit(EventType)
  
EndProcedure

Procedure ButtonDelete(EventType)
  
EndProcedure

Procedure ButtonUp(EventType)
  
EndProcedure

Procedure ButtonDown(EventType)
  
EndProcedure

Procedure updateGadgets()
  Static lastUpdate = 0
  Protected elapsedTime, totalTime, remainingTime
  
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
    ; only one job at a time, so just check for jobs that are not done
    ; if there could be multiple jobs at a time, check also for running jobs
    If Not jobs()\done
      *CurrentJob = jobs() ; copy pointer to this element
      Break ; leave loop
    EndIf
  Next
  UnlockMutex(mutexJobs)
  
  SetGadgetText(StringInput, *CurrentJob\file\source$)
  SetGadgetText(StringOutput, *CurrentJob\file\destination$)
  SetGadgetText(StringPosition, "00:00:00 / 00:00:00")
  SetGadgetText(StringFrames, "0 / 0")
  SetGadgetText(StringTimeElapsed, "00:00:00")
  SetGadgetText(StringTimeRemaining, "00:00:00")
  SetGadgetState(ProgressBarVideo, 0)
  
  HideWindow(WindowTranscode, #False)
  
  CreateThread(@ffmpeg(), *CurrentJob)
  
EndProcedure


init()

OpenWindowMain()
OpenWindowTranscode()
EnableGadgetDrop(GadgetQueue, #PB_Drop_Files, #PB_Drag_Copy|#PB_Drag_Move|#PB_Drag_Link)

HideWindow(WindowMain, #False)

;{ --------- TEST
LockMutex(mutexJobs)
ResetList(jobs())
AddElement(jobs())
With jobs()
  \file\source$       = "C:\Users\Alexander\Desktop\test.mp4"
  \file\destination$  = "C:\Users\Alexander\Desktop\out.mkv"
EndWith
UnlockMutex(mutexJobs)

DeleteFile("C:\Users\Alexander\Desktop\out.mkv")
;startNextJob()
;}


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
        
      EndIf
  EndSelect
  
ForEver
End
; IDE Options = PureBasic 5.11 (Windows - x64)
; CursorPosition = 193
; FirstLine = 150
; Folding = xH9
; EnableXP