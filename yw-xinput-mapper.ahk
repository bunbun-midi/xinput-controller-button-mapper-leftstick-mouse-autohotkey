#NoEnv
#SingleInstance Force
#Persistent
#InstallKeybdHook
#InstallMouseHook
SetBatchLines, -1
ListLines, Off
SendMode, Input
SetWorkingDir, %A_ScriptDir%

global XInputDll := ""
global Sensitivity := 12.0
global DeadzonePercent := 12
global TriggerThreshold := 30
global Enabled := 1
global RepeatInterval := 35

global AccumMouseX := 0.0
global AccumMouseY := 0.0
global PreviousButtons := 0
global PreviousLeftTrigger := 0
global PreviousRightTrigger := 0
global LastStatus := ""

global SelectedAction := "A"
global ActionText := {}
global ActionRepeat := {}
global HeldRawKeys := {}

global MappingDirectory := A_AppData "\XInputButtonMouse"
global MappingRepeatFile := A_AppData "\XInputButtonMouse\repeat.ini"

; ============================================================
; Load XInput
; ============================================================

hModule := DllCall("LoadLibrary", "Str", "xinput1_4.dll", "Ptr")

if (hModule)
    XInputDll := "xinput1_4.dll"

if (XInputDll = "") {
    hModule := DllCall("LoadLibrary", "Str", "xinput1_3.dll", "Ptr")

    if (hModule)
        XInputDll := "xinput1_3.dll"
}

if (XInputDll = "") {
    hModule := DllCall("LoadLibrary", "Str", "xinput9_1_0.dll", "Ptr")

    if (hModule)
        XInputDll := "xinput9_1_0.dll"
}

if (XInputDll = "") {
    MsgBox, 16, XInput Error, Could not load an XInput DLL.
    ExitApp
}

; ============================================================
; Initialize mappings
; ============================================================

ActionText["DPad-Up"] := ""
ActionText["DPad-Left"] := ""
ActionText["DPad-Down"] := ""
ActionText["DPad-Right"] := ""
ActionText["L3"] := ""
ActionText["R3"] := ""
ActionText["A"] := ""
ActionText["B"] := ""
ActionText["X"] := ""
ActionText["Y"] := ""
ActionText["L1"] := ""
ActionText["R1"] := ""
ActionText["L2"] := ""
ActionText["R2"] := ""
ActionText["Start"] := ""
ActionText["Back"] := ""

ActionRepeat["DPad-Up"] := 0
ActionRepeat["DPad-Left"] := 0
ActionRepeat["DPad-Down"] := 0
ActionRepeat["DPad-Right"] := 0
ActionRepeat["L3"] := 0
ActionRepeat["R3"] := 0
ActionRepeat["A"] := 0
ActionRepeat["B"] := 0
ActionRepeat["X"] := 0
ActionRepeat["Y"] := 0
ActionRepeat["L1"] := 0
ActionRepeat["R1"] := 0
ActionRepeat["L2"] := 0
ActionRepeat["R2"] := 0
ActionRepeat["Start"] := 0
ActionRepeat["Back"] := 0

LoadSavedMappings()

; ============================================================
; Main GUI
; ============================================================

Gui, New, +AlwaysOnTop +MinSize450x390, XInput Left Stick Mouse
Gui, Font, s10, Segoe UI

Gui, Add, Checkbox, xm ym w410 vEnabled gEnabledChanged Checked, Enable left-stick mouse control
Gui, Add, Text, xm y+18 w140, Sensitivity
Gui, Add, Slider, x+5 yp-3 w275 vSensitivitySlider gSensitivityChanged Range1-300 ToolTip, 120
Gui, Add, Text, xm y+14 w410 vSensitivityLabel, Sensitivity: 12.0

Gui, Add, Text, xm y+16 w140, Dead zone
Gui, Add, Slider, x+5 yp-3 w275 vDeadzoneSlider gDeadzoneChanged Range0-50 ToolTip, 12
Gui, Add, Text, xm y+14 w410 vDeadzoneLabel, Dead zone: 12 percent

Gui, Add, Text, xm y+16 w140, Trigger threshold
Gui, Add, Slider, x+5 yp-3 w275 vTriggerSlider gTriggerChanged Range1-255 ToolTip, 30
Gui, Add, Text, xm y+14 w410 vTriggerLabel, Trigger threshold: 30

Gui, Add, GroupBox, xm y+18 w420 h125, Controller state
Gui, Add, Text, xp+15 yp+25 w390 h90 vStatusText, Starting XInput polling...
Gui, Add, Button, xm y+15 w210 h30 gShowActions, Open button action editor
Gui, Add, Text, x+15 yp+7 w195, DLL: %XInputDll%

Gui, Show, w450 h410, XInput Left Stick Mouse

GuiControl,, SensitivitySlider, 120
GuiControl,, DeadzoneSlider, 12
GuiControl,, TriggerSlider, 30

Gosub, SensitivityChanged
Gosub, DeadzoneChanged
Gosub, TriggerChanged
Gosub, EnabledChanged

; ============================================================
; Action editor GUI
; ============================================================

Gosub, CreateActionGui
Gui, 2:Show, w720 h560, XInput Button Actions

Gosub, PollXInput
SetTimer, PollXInput, 15
SetTimer, RepeatHeldRawKeys, %RepeatInterval%
return

; ============================================================
; XInput polling
; ============================================================

PollXInput:
    Critical

    connectedSlot := -1
    VarSetCapacity(state, 16, 0)

    Loop, 4 {
        slot := A_Index - 1
        result := DllCall(XInputDll "\XInputGetState", "UInt", slot, "Ptr", &state, "UInt")

        if (result = 0) {
            connectedSlot := slot
            break
        }
    }

    if (connectedSlot < 0) {
        ReleaseAllHeldRawKeys()
        PreviousButtons := 0
        PreviousLeftTrigger := 0
        PreviousRightTrigger := 0
        AccumMouseX := 0.0
        AccumMouseY := 0.0
        UpdateStatus("No XInput controller connected.`nDLL: " XInputDll)
        return
    }

    packet := NumGet(state, 0, "UInt")
    buttons := NumGet(state, 4, "UShort")
    leftTrigger := NumGet(state, 6, "UChar")
    rightTrigger := NumGet(state, 7, "UChar")
    leftX := NumGet(state, 8, "Short")
    leftY := NumGet(state, 10, "Short")

    HandleButtonActions(buttons, leftTrigger, rightTrigger)

    if (!Enabled) {
        AccumMouseX := 0.0
        AccumMouseY := 0.0
        UpdateStatus("Slot " connectedSlot " connected.`nMouse control disabled.`nPacket: " packet)
        return
    }

    normalizedX := leftX / 32768.0
    normalizedY := leftY / 32768.0
    magnitude := Sqrt(normalizedX * normalizedX + normalizedY * normalizedY)
    deadzone := DeadzonePercent / 100.0

    if (magnitude <= deadzone) {
        AccumMouseX := 0.0
        AccumMouseY := 0.0
        UpdateStatus("Slot " connectedSlot " connected.`nStick centered.`nRaw: " leftX ", " leftY)
        return
    }

    if (magnitude > 1.0)
        magnitude := 1.0

    remappedMagnitude := (magnitude - deadzone) / (1.0 - deadzone)

    if (remappedMagnitude < 0.0)
        remappedMagnitude := 0.0

    if (remappedMagnitude > 1.0)
        remappedMagnitude := 1.0

    directionX := normalizedX / magnitude
    directionY := normalizedY / magnitude
    processedX := directionX * remappedMagnitude
    processedY := directionY * remappedMagnitude

    AccumMouseX += processedX * Sensitivity
    AccumMouseY += -processedY * Sensitivity

    moveX := TruncTowardZero(AccumMouseX)
    moveY := TruncTowardZero(AccumMouseY)

    if (moveX != 0)
        AccumMouseX -= moveX

    if (moveY != 0)
        AccumMouseY -= moveY

    if (moveX != 0 || moveY != 0)
        MouseMove, %moveX%, %moveY%, 0, R

    status := "Slot " connectedSlot " connected.`n"
    status .= "Packet: " packet "`n"
    status .= "Buttons: " GetButtonNames(buttons) "`n"
    status .= "Stick: " leftX ", " leftY "`n"
    status .= "Mouse: " moveX ", " moveY
    UpdateStatus(status)
return

; ============================================================
; Button handling
; ============================================================

HandleButtonActions(buttons, leftTrigger, rightTrigger) {
    global PreviousButtons
    global PreviousLeftTrigger
    global PreviousRightTrigger
    global TriggerThreshold

    CheckButtonState(0x0001, "DPad-Up", buttons, PreviousButtons)
    CheckButtonState(0x0002, "DPad-Down", buttons, PreviousButtons)
    CheckButtonState(0x0004, "DPad-Left", buttons, PreviousButtons)
    CheckButtonState(0x0008, "DPad-Right", buttons, PreviousButtons)
    CheckButtonState(0x0040, "L3", buttons, PreviousButtons)
    CheckButtonState(0x0080, "R3", buttons, PreviousButtons)
    CheckButtonState(0x0100, "L1", buttons, PreviousButtons)
    CheckButtonState(0x0200, "R1", buttons, PreviousButtons)
    CheckButtonState(0x1000, "A", buttons, PreviousButtons)
    CheckButtonState(0x2000, "B", buttons, PreviousButtons)
    CheckButtonState(0x4000, "X", buttons, PreviousButtons)
    CheckButtonState(0x8000, "Y", buttons, PreviousButtons)

    if (leftTrigger >= TriggerThreshold && PreviousLeftTrigger < TriggerThreshold)
        HandleMappedButtonDown("L2")

    if (leftTrigger < TriggerThreshold && PreviousLeftTrigger >= TriggerThreshold)
        HandleMappedButtonUp("L2")

    if (rightTrigger >= TriggerThreshold && PreviousRightTrigger < TriggerThreshold)
        HandleMappedButtonDown("R2")

    if (rightTrigger < TriggerThreshold && PreviousRightTrigger >= TriggerThreshold)
        HandleMappedButtonUp("R2")

    PreviousButtons := buttons
    PreviousLeftTrigger := leftTrigger
    PreviousRightTrigger := rightTrigger
}

CheckButtonState(mask, actionName, currentButtons, previousButtons) {
    isPressed := currentButtons & mask
    wasPressed := previousButtons & mask

    if (isPressed && !wasPressed)
        HandleMappedButtonDown(actionName)

    if (!isPressed && wasPressed)
        HandleMappedButtonUp(actionName)
}

HandleMappedButtonDown(actionName) {
    global ActionText
    global ActionRepeat
    global HeldRawKeys

    source := Trim(ActionText[actionName])

    if (IsRawKeyMapping(source)) {
        keyName := GetRawKeyName(source)
        downText := "{" keyName " down}"
        SendInput, %downText%

        if (ActionRepeat[actionName])
            HeldRawKeys[actionName] := keyName

        return
    }

    RunMappedAction(actionName)
}

HandleMappedButtonUp(actionName) {
    global HeldRawKeys

    if (!HeldRawKeys.HasKey(actionName))
        return

    keyName := HeldRawKeys[actionName]
    upText := "{" keyName " up}"
    SendInput, %upText%
    HeldRawKeys.Delete(actionName)
}

RepeatHeldRawKeys:
    for actionName, keyName in HeldRawKeys {
        repeatText := "{" keyName "}"
        SendInput, %repeatText%
    }
return

ReleaseAllHeldRawKeys() {
    global HeldRawKeys

    for actionName, keyName in HeldRawKeys {
        upText := "{" keyName " up}"
        SendInput, %upText%
    }

    HeldRawKeys := {}
}

IsRawKeyMapping(source) {
    if (source = "")
        return false

    return RegExMatch(source, "^\{[^{}[:space:]]+\}$")
}

GetRawKeyName(source) {
    return SubStr(source, 2, StrLen(source) - 2)
}

; ============================================================
; Action editor GUI
; ============================================================

CreateActionGui:
    Gui, 2:New, +Resize +MinSize700x540, XInput Button Actions
    Gui, 2:Font, s9, Segoe UI

    Gui, 2:Add, Text, xm ym, Controller input
    Gui, 2:Add, ListBox, xm y+5 w180 h390 vActionList gActionSelected, DPad-Up|DPad-Left|DPad-Down|DPad-Right|L3|R3|A|B|X|Y|L1|R1|L2|R2|Start|Back

    Gui, 2:Add, Text, x205 yp w480, Arbitrary AutoHotkey v1 source
    Gui, 2:Add, Edit, x205 y+5 w480 h350 vActionEditor WantReturn WantTab HScroll

    Gui, 2:Add, Checkbox, x205 y+10 w300 vRepeatCurrent gRepeatChanged, Repeat raw key while held
    Gui, 2:Add, Text, x205 y+12 w180, Repeat rate
    Gui, 2:Add, Slider, x385 yp-3 w250 vRepeatSlider gRepeatRateChanged Range20-200 ToolTip, 35
    Gui, 2:Add, Text, x205 y+12 w430 vRepeatLabel, Repeat interval: 35 ms

    Gui, 2:Add, Button, xm y+12 w100 h30 gSaveAction, Save
    Gui, 2:Add, Button, x+10 yp w100 h30 gRunSelectedAction, Test
    Gui, 2:Add, Button, x+10 yp w100 h30 gClearAction, Clear

    GuiControl, 2:, ActionList, A
    SelectedAction := "A"
    GuiControl, 2:, ActionEditor,
    initialRepeat := ActionRepeat["A"]
	GuiControl, 2:, RepeatCurrent, %initialRepeat%
return

ShowActions:
    Gui, 2:Show, w720 h560, XInput Button Actions
return

; ============================================================
; Per-button editor handling
; ============================================================

ActionSelected:
    GuiControlGet, currentText, 2:, ActionEditor
    GuiControlGet, currentRepeat, 2:, RepeatCurrent

    ActionText[SelectedAction] := currentText
    ActionRepeat[SelectedAction] := currentRepeat ? 1 : 0
    SaveMapping(SelectedAction)

    GuiControlGet, newAction, 2:, ActionList

    if (newAction = "")
        return

    SelectedAction := newAction
    newText := ActionText[SelectedAction]
    newRepeat := ActionRepeat[SelectedAction]

    GuiControl, 2:, ActionEditor, %newText%
    GuiControl, 2:, RepeatCurrent, %newRepeat%
return

SaveAction:
    GuiControlGet, currentText, 2:, ActionEditor
    GuiControlGet, currentRepeat, 2:, RepeatCurrent

    ActionText[SelectedAction] := currentText
    ActionRepeat[SelectedAction] := currentRepeat ? 1 : 0
    SaveMapping(SelectedAction)
return

ClearAction:
    ActionText[SelectedAction] := ""
    ActionRepeat[SelectedAction] := 0
    SaveMapping(SelectedAction)

    GuiControl, 2:, ActionEditor,
    GuiControl, 2:, RepeatCurrent, 0
return

RunSelectedAction:
    Gosub, SaveAction
    RunMappedAction(SelectedAction)
return

RepeatChanged:
    GuiControlGet, currentRepeat, 2:, RepeatCurrent
    ActionRepeat[SelectedAction] := currentRepeat ? 1 : 0
    SaveMapping(SelectedAction)
return

RepeatRateChanged:
    GuiControlGet, RepeatInterval, 2:, RepeatSlider

    SetTimer, RepeatHeldRawKeys, Off
    SetTimer, RepeatHeldRawKeys, %RepeatInterval%

    text := "Repeat interval: " RepeatInterval " ms"
    GuiControl, 2:, RepeatLabel, %text%
return

2GuiClose:
2GuiEscape:
    Gui, 2:Hide
return

; ============================================================
; Save and load mappings
; ============================================================

LoadSavedMappings() {
    global ActionText
    global ActionRepeat
    global MappingDirectory
    global MappingRepeatFile

    FileCreateDir, %MappingDirectory%
    FileEncoding, UTF-8

    for actionName, unused in ActionText {
        safeName := SanitizeMappingName(actionName)
        filePath := MappingDirectory "\" safeName ".ahk"

        if (FileExist(filePath)) {
            FileRead, savedSource, %filePath%
            ActionText[actionName] := savedSource
        }

        IniRead, repeatValue, %MappingRepeatFile%, Repeat, %actionName%, 0

        if (repeatValue = "ERROR")
            repeatValue := 0

        ActionRepeat[actionName] := repeatValue ? 1 : 0
    }
}

SaveMapping(actionName) {
    global ActionText
    global ActionRepeat
    global MappingDirectory
    global MappingRepeatFile

    FileCreateDir, %MappingDirectory%
    FileEncoding, UTF-8

    safeName := SanitizeMappingName(actionName)
    filePath := MappingDirectory "\" safeName ".ahk"
    source := ActionText[actionName]

    FileDelete, %filePath%
    FileAppend, %source%, %filePath%

    IniWrite, % ActionRepeat[actionName], %MappingRepeatFile%, Repeat, %actionName%
}

SaveAllMappings() {
    global ActionText

    for actionName, unused in ActionText
        SaveMapping(actionName)
}

SanitizeMappingName(name) {
    StringReplace, name, name, %A_Space%, _, All
    StringReplace, name, name, -, _, All
    StringReplace, name, name, /, _, All
    StringReplace, name, name, \, _, All
    return name
}

; ============================================================
; Execute arbitrary multiline AHK source
; ============================================================

RunMappedAction(actionName) {
    global ActionText

    source := ActionText[actionName]

    if (source = "")
        return

    tempDirectory := A_Temp "\XInputButtonActions"
    FileCreateDir, %tempDirectory%

    safeName := SanitizeMappingName(actionName)
    filePath := tempDirectory "\" safeName ".ahk"

    FileDelete, %filePath%
    FileAppend, %source%`r`n, %filePath%

    command := """" A_AhkPath """ """ filePath """"
    Run, %command%,, UseErrorLevel

    if (ErrorLevel)
        TrayTip, XInput Action Error, Could not launch %actionName%, 5, 17
}

; ============================================================
; GUI controls
; ============================================================

SensitivityChanged:
    GuiControlGet, value,, SensitivitySlider
    Sensitivity := value / 10.0
    text := "Sensitivity: " Format("{:.1f}", Sensitivity)
    GuiControl,, SensitivityLabel, %text%
return

DeadzoneChanged:
    GuiControlGet, DeadzonePercent,, DeadzoneSlider
    text := "Dead zone: " DeadzonePercent " percent"
    GuiControl,, DeadzoneLabel, %text%
return

TriggerChanged:
    GuiControlGet, TriggerThreshold,, TriggerSlider
    text := "Trigger threshold: " TriggerThreshold
    GuiControl,, TriggerLabel, %text%
return

EnabledChanged:
    GuiControlGet, Enabled,, Enabled

    if (!Enabled) {
        AccumMouseX := 0.0
        AccumMouseY := 0.0
        UpdateStatus("Mouse control disabled.")
    }
return

; ============================================================
; Helpers
; ============================================================

TruncTowardZero(value) {
    if (value >= 0)
        return Floor(value)

    return Ceil(value)
}

UpdateStatus(text) {
    global LastStatus

    if (text = LastStatus)
        return

    LastStatus := text
    GuiControl,, StatusText, %text%
}

GetButtonNames(buttons) {
    names := ""

    if (buttons & 0x0001)
        names .= "DPad-Up "
    if (buttons & 0x0002)
        names .= "DPad-Down "
    if (buttons & 0x0004)
        names .= "DPad-Left "
    if (buttons & 0x0008)
        names .= "DPad-Right "
    if (buttons & 0x0010)
        names .= "Start "
    if (buttons & 0x0020)
        names .= "Back "
    if (buttons & 0x0040)
        names .= "L3 "
    if (buttons & 0x0080)
        names .= "R3 "
    if (buttons & 0x0100)
        names .= "L1 "
    if (buttons & 0x0200)
        names .= "R1 "
    if (buttons & 0x1000)
        names .= "A "
    if (buttons & 0x2000)
        names .= "B "
    if (buttons & 0x4000)
        names .= "X "
    if (buttons & 0x8000)
        names .= "Y "

    if (names = "")
        names := "(none)"

    return RTrim(names)
}

; ============================================================
; Exit
; ============================================================

GuiClose:
GuiEscape:
    GuiControlGet, currentText, 2:, ActionEditor
    GuiControlGet, currentRepeat, 2:, RepeatCurrent

    ActionText[SelectedAction] := currentText
    ActionRepeat[SelectedAction] := currentRepeat ? 1 : 0
    SaveAllMappings()
    ReleaseAllHeldRawKeys()

    SetTimer, PollXInput, Off
    SetTimer, RepeatHeldRawKeys, Off
    ExitApp
return