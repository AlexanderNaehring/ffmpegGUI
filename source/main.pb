EnableExplicit

XIncludeFile "WindowMain.pbf"

Global Event


Procedure exit()
  End  
EndProcedure

Procedure GadgetQueue(EventType)
  
EndProcedure

Procedure ButtonStartStop(EventType)
  
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



OpenWindowMain()

HideWindow(WindowMain, #False)

Repeat
  Event = WaitWindowEvent(50)
  If Not WindowMain_Events(Event)
    exit()
  EndIf
  
ForEver

; IDE Options = PureBasic 5.11 (Windows - x64)
; CursorPosition = 23
; Folding = --
; EnableXP