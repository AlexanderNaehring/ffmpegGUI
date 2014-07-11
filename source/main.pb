EnableExplicit

XIncludeFile "WindowMain.pbf"

#GUI_UPDATE = 100

Global Event

Procedure init()
  ; search for ffmpeg binary
  Debug RunProgram("ffmpeg")
  Debug RunProgram("ffmpeg.exe")
  Debug RunProgram("./ffmpeg")
  Debug RunProgram("./ffmpeg.exe")
  
  Debug FileSize("ffmpeg")
  Debug FileSize("ffmpeg.exe")
  
  Debug ProgramFilename()
  Debug GetCurrentDirectory()
  
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

Procedure ffmpeg()
  Protected prog, out$, command$, arg$, payload$
  command$ = GetCurrentDirectory()+"sfsend"
  arg$ = "localhost 9001 0x00 0xff 0xff 0xff 0xff 0x04 0x22 0x06 " + payload$
  ;addlog(command$ + " " + arg$)
  prog = RunProgram(command$, arg$, "./", #PB_Program_Open|#PB_Program_Read|#PB_Program_Error)
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

Repeat
  updateGadgets()
  Event = WaitWindowEvent(50)
  If Not WindowMain_Events(Event)
    exit()
  EndIf
  
  
ForEver
End
; IDE Options = PureBasic 5.11 (Windows - x64)
; CursorPosition = 22
; Folding = 6--
; EnableXP