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
EndStructure

Global CurrentJobAbort  ; global variable, set to true if transcoding should be canceled
Global CurrentJobID     ; stores jobID of currently transcoding job
Global CurrentJobFFMPEG ; stores program ID of ffmpeg
Global *CurrentJob.job  ; pointer to current job in list()
Global NewList  jobs.job()  ; list of all jobs
Global mutexJobs = CreateMutex()

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
  Repeat
    Delay(1)
    If Not IsProgram(prog) Or CurrentJobAbort
      Break ; either ffmpeg exited or job should be canceled
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
    Debug "kill ffmpeg"
    KillProgram(prog)
  EndIf
  CloseProgram(prog)
  
EndProcedure


Procedure GadgetQueue(EventType)
  
EndProcedure

Procedure ButtonStartStop(EventType)
  addLog("start/stop queue")
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
  
  If lastUpdate < ElapsedMilliseconds() - #GUI_UPDATE
    lastUpdate = ElapsedMilliseconds()
    
    If *CurrentJob
      SetGadgetText(StringPosition, *CurrentJob\durationCurrent$+" / "+*CurrentJob\durationTotal$)
      SetGadgetText(StringFrames, "0 / 0")
      SetGadgetText(StringTimeElapsed, "00:00:00")
      SetGadgetText(StringTimeRemaining, "00:00:00")
      If *CurrentJob\durationSecondsTotal        
        SetGadgetState(ProgressBarVideo, 100 * *CurrentJob\durationSecondsCurrent / *CurrentJob\durationSecondsTotal)
      EndIf
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
  
  *CurrentJob\startTime = Date()
  
  SetGadgetText(StringInput, *CurrentJob\file\source$)
  SetGadgetText(StringOutput, *CurrentJob\file\destination$)
  SetGadgetText(StringPosition, "00:00:00 / 00:00:00")
  SetGadgetText(StringFrames, "0 / 0")
  SetGadgetText(StringTimeElapsed, "00:00:00")
  SetGadgetText(StringTimeRemaining, "00:00:00")
  
  SetGadgetState(ProgressBarVideo, 0)
  
  HideWindow(WindowTranscode, #False)
  
  CreateThread(@ffmpeg(),*CurrentJob)
  
EndProcedure


init()

OpenWindowMain()
OpenWindowTranscode()

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
startNextJob()
;}


Repeat
  updateGadgets()
  Event = WaitWindowEvent(100)
  
  Select EventWindow()
    Case WindowMain
      If Not WindowMain_Events(Event)
        exit()
      EndIf
    Case WindowTranscode
      If Not WindowTranscode_Events(Event)
        
      EndIf
  EndSelect
  
ForEver
End
; IDE Options = PureBasic 5.11 (Windows - x64)
; CursorPosition = 124
; FirstLine = 75
; Folding = 8--
; EnableXP