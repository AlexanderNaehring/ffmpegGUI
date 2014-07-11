EnableExplicit

XIncludeFile "WindowMain.pbf"




#GUI_UPDATE = 100

Global Event
Global dirP$, dirC$

Structure file
  source$
  destination$
EndStructure

Structure audio
  codec$
  q.i
EndStructure

Structure video
  codec$
  crf.i
  scale$
  preset$
  tune$
  profile$
EndStructure

Structure job
  jobID.i
  programID.i
  file.file
  audio.audio
  video.video
EndStructure


Procedure init()
  ; search for ffmpeg binary
  dirP$ = ProgramFilename()
  dirC$ = GetCurrentDirectory()
  Debug dirP$
  Debug dirC$
  
EndProcedure


Procedure exit()
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
  c$ = c$ + " -acodec "+*job\audio\codec$
  c$ = c$ + " -aq "+Str(*job\audio\q)
  c$ = c$ + " -vcodec "+*job\video\codec$
  c$ = c$ + " -crf "+Str(*job\video\crf)
  If *job\video\scale$
    c$ = c$ + " "+*job\video\scale$
  EndIf
  c$ = c$ + " -preset "+*job\video\preset$
  c$ = c$ + " -tune "+*job\video\tune$
  c$ = c$ + " -profile:v "+*job\video\profile$
  c$ = c$ + " -threads 4"
  c$ = c$ + " "+#DQUOTE$+*job\file\destination$+#DQUOTE$

  Debug c$
  prog = RunProgram("./ffmpeg", c$, "./", #PB_Program_Open|#PB_Program_Read|#PB_Program_Error|#PB_Program_Write|#PB_Program_Hide)
  If Not prog
    Debug "error"
    ProcedureReturn
  EndIf
  
  Protected totalTime
  Protected out$
  While ProgramRunning(prog)
    out$ = ReadProgramError(prog)
    If out$
      Debug out$
      
      If FindString(out$, "Duration:")
        out$ = RemoveString(out$, "Duration:")
        out$ = Trim(Left(out$, FindString(out$, ".")-1))
        totalTime = getSeconds(out$)
      EndIf
      
      If FindString(out$, "frame")
        out$ = Mid(out$, FindString(out$, "time=") + 5)
        out$ = Left(out$, FindString(out$, ".")-1)
        Debug Str(100*getSeconds(out$)/totalTime) + " %"
      EndIf
      
    EndIf
    If AvailableProgramOutput(prog)
      out$ = ReadProgramString(prog)
      If out$
        Debug out$
      EndIf
    EndIf
  Wend
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
    
    
  EndIf
EndProcedure

init()

OpenWindowMain()

HideWindow(WindowMain, #False)


; test
Define testjob.job
With testjob
  \jobId              = 1
  \programID          = 0 ; set by ffmpeg call!
  \file\source$       = "C:\Users\Alexander\Desktop\test.mp4"
  \file\destination$  = "C:\Users\Alexander\Desktop\out.mkv"
  \audio\codec$       = "libvorbis"
  \audio\q            = 2
  \video\codec$       = "libx264"
  \video\crf          = 21
  \video\scale$       = "" ; " -vf scale=-1:720"
  \video\preset$      = "slow"
  \video\tune$        = "film"
  \video\profile$     = "high"
EndWith
DeleteFile("C:\Users\Alexander\Desktop\out.mkv")
CreateThread(@ffmpeg(),@testjob)

Repeat
  updateGadgets()
  Event = WaitWindowEvent(50)
  If Not WindowMain_Events(Event)
    exit()
  EndIf
  
  
ForEver
End
; IDE Options = PureBasic 5.11 (Windows - x64)
; CursorPosition = 120
; FirstLine = 71
; Folding = 6--
; EnableXP