#NoEnv
#SingleInstance Force
#Persistent
SetBatchLines, -1
ListLines, Off
SendMode, Input
SetWorkingDir, %A_ScriptDir%

global XInputDll := ""
global Sensitivity := 12.0
global Deadzone := 12
global TriggerThreshold := 30
global RepeatInterval := 35
global Enabled := 1

global AccumX := 0.0
global AccumY := 0.0
global PreviousButtons := 0
global PreviousLT := 0
global PreviousRT := 0
global HeldRawKeys := {}
global ActionText := {}
global ActionRepeat := {}
global SelectedAction := "A"
global MappingDirectory := A_AppData "\XInputButtonMouse"
global RepeatFile := A_AppData "\XInputButtonMouse\repeat.ini"

; ------------------------------------------------------------
; XInput DLL
; ------------------------------------------------------------

h := DllCall("LoadLibrary", "Str", "xinput1_4.dll", "Ptr")
if (h)
    XInputDll := "xinput1_4.dll"

if (XInputDll = "") {
    h := DllCall("LoadLibrary", "Str", "xinput1_3.dll", "Ptr")
    if (h)
        XInputDll := "xinput1_3.dll"
}

if (XInputDll = "") {
    h := DllCall("LoadLibrary", "Str", "xinput9_1_0.dll", "Ptr")
    if (h)
        XInputDll := "xinput9_1_0.dll"
}

if (XInputDll = "") {
    MsgBox, 16, Error, Could not load an XInput DLL.
    ExitApp
}

; ------------------------------------------------------------
; Initialize mappings
; ------------------------------------------------------------

for _, name in ["DPad-Up", "DPad-Left", "DPad-Down", "DPad-Right", "L3", "R3", "A", "B", "X", "Y", "L1", "R1", "L2", "R2", "Start", "Back"] {
    ActionText[name] := ""
    ActionRepeat[name] := 0
}

LoadMappings()

; ------------------------------------------------------------
; Main GUI
; ------------------------------------------------------------

Gui, New, +AlwaysOnTop, XInput Left Stick Mouse
Gui, Font, s10, Segoe UI

Gui, Add, Checkbox, xm ym vEnabled gEnabledChanged Checked, Enable left-stick mouse control
Gui, Add, Text, xm y+15 w120, Sensitivity
Gui, Add, Slider, x+5 yp-3 w260 vSensitivitySlider gSensitivityChanged Range1-300, 120
Gui, Add, Text, xm y+10 w400 vSensitivityLabel, Sensitivity: 12.0

Gui, Add, Text, xm y+12 w120, Dead zone
Gui, Add, Slider, x+5 yp-3 w260 vDeadzoneSlider gDeadzoneChanged Range0-50, 12
Gui, Add, Text, xm y+10 w400 vDeadzoneLabel, Dead zone: 12 percent

Gui, Add, Text, xm y+12 w120, Trigger threshold
Gui, Add, Slider, x+5 yp-3 w260 vTriggerSlider gTriggerChanged Range1-255, 30
Gui, Add, Text, xm y+10 w400 vTriggerLabel, Trigger threshold: 30

Gui, Add, GroupBox, xm y+15 w410 h110, Status
Gui, Add, Text, xp+15 yp+25 w380 h80 vStatus, Starting...
Gui, Add, Button, xm y+15 w210 gShowActions, Open button action editor

Gui, Show, w440 h365, XInput Left Stick Mouse

Gosub, SensitivityChanged
Gosub, DeadzoneChanged
Gosub, TriggerChanged
Gosub, CreateActionGui

Gui, 2:Show, w720 h560, XInput Button Actions

Gosub, PollXInput
SetTimer, PollXInput, 15
SetTimer, RepeatHeldRawKeys, %RepeatInterval%
return

; ------------------------------------------------------------
; XInput polling
; ------------------------------------------------------------

PollXInput:
    Critical
    connected := -1
    VarSetCapacity(state, 16, 0)

    Loop, 4 {
        slot := A_Index - 1
        result := DllCall(XInputDll "\XInputGetState", "UInt", slot, "Ptr", &state, "UInt")

        if (result = 0) {
            connected := slot
            break
        }
    }

    if (connected < 0) {
        ReleaseAllHeldRawKeys()
        PreviousButtons := 0
        PreviousLT := 0
        PreviousRT := 0
        UpdateStatus("No XInput controller connected.")
        return
    }

    buttons := NumGet(state, 4, "UShort")
    lt := NumGet(state, 6, "UChar")
    rt := NumGet(state, 7, "UChar")
    leftX := NumGet(state, 8, "Short")
    leftY := NumGet(state, 10, "Short")

    HandleButtons(buttons, lt, rt)

    if (!Enabled)
        return

    x := leftX / 32768.0
    y := leftY / 32768.0
    magnitude := Sqrt(x * x + y * y)
    dz := Deadzone / 100.0

    if (magnitude <= dz) {
        AccumX := 0.0
        AccumY := 0.0
        UpdateStatus("Slot " connected " connected.`nStick centered.`nRaw: " leftX ", " leftY)
        return
    }

    if (magnitude > 1.0)
        magnitude := 1.0

    amount := (magnitude - dz) / (1.0 - dz)
    x := (x / magnitude) * amount
    y := (y / magnitude) * amount

    AccumX += x * Sensitivity
    AccumY += -y * Sensitivity

    moveX := TruncZero(AccumX)
    moveY := TruncZero(AccumY)

    AccumX -= moveX
    AccumY -= moveY

    if (moveX || moveY)
        MouseMove, %moveX%, %moveY%, 0, R

    UpdateStatus("Slot " connected " connected.`nRaw: " leftX ", " leftY "`nMouse: " moveX ", " moveY)
return

; ------------------------------------------------------------
; Button state handling
; ------------------------------------------------------------

HandleButtons(buttons, lt, rt) {
    global PreviousButtons, PreviousLT, PreviousRT, TriggerThreshold

    CheckButton(0x0001, "DPad-Up", buttons, PreviousButtons)
    CheckButton(0x0002, "DPad-Down", buttons, PreviousButtons)
    CheckButton(0x0004, "DPad-Left", buttons, PreviousButtons)
    CheckButton(0x0008, "DPad-Right", buttons, PreviousButtons)
    CheckButton(0x0040, "L3", buttons, PreviousButtons)
    CheckButton(0x0080, "R3", buttons, PreviousButtons)
    CheckButton(0x0100, "L1", buttons, PreviousButtons)
    CheckButton(0x0200, "R1", buttons, PreviousButtons)
    CheckButton(0x1000, "A", buttons, PreviousButtons)
    CheckButton(0x2000, "B", buttons, PreviousButtons)
    CheckButton(0x4000, "X", buttons, PreviousButtons)
    CheckButton(0x8000, "Y", buttons, PreviousButtons)

    if (lt >= TriggerThreshold && PreviousLT < TriggerThreshold)
        ButtonDown("L2")

    if (lt < TriggerThreshold && PreviousLT >= TriggerThreshold)
        ButtonUp("L2")

    if (rt >= TriggerThreshold && PreviousRT < TriggerThreshold)
        ButtonDown("R2")

    if (rt < TriggerThreshold && PreviousRT >= TriggerThreshold)
        ButtonUp("R2")

    PreviousButtons := buttons
    PreviousLT := lt
    PreviousRT := rt
}

CheckButton(mask, name, current, previous) {
    if ((current & mask) && !(previous & mask))
        ButtonDown(name)

    if (!(current & mask) && (previous & mask))
        ButtonUp(name)
}

ButtonDown(name) {
    global ActionText, HeldRawKeys

    source := Trim(ActionText[name])

    if (IsRawKey(source)) {
        key := RawKeyName(source)

        ; Always store the key, even when repeat is disabled.
        HeldRawKeys[name] := key

        SendInput, % "{" key " down}"
        return
    }

    RunAction(name)
}

ButtonUp(name) {
    global HeldRawKeys

    if (!HeldRawKeys.HasKey(name))
        return

    key := HeldRawKeys[name]
    SendInput, % "{" key " up}"
    HeldRawKeys.Delete(name)
}

RepeatHeldRawKeys:
    global HeldRawKeys, ActionRepeat

    for name, key in HeldRawKeys {
        if (ActionRepeat[name])
            SendInput, % "{" key "}"
    }
return

ReleaseAllHeldRawKeys() {
    global HeldRawKeys

    for name, key in HeldRawKeys
        SendInput, % "{" key " up}"

    HeldRawKeys := {}
}

IsRawKey(text) {
    return text != "" && RegExMatch(text, "^\{[^{}[:space:]]+\}$")
}

RawKeyName(text) {
    return SubStr(text, 2, StrLen(text) - 2)
}

; ------------------------------------------------------------
; Action editor
; ------------------------------------------------------------

CreateActionGui:
    Gui, 2:New, +MinSize700x540, XInput Button Actions
    Gui, 2:Font, s9, Segoe UI

    Gui, 2:Add, Text, xm ym, Controller input
    Gui, 2:Add, ListBox, xm y+5 w180 h390 vActionList gActionSelected, DPad-Up|DPad-Left|DPad-Down|DPad-Right|L3|R3|A|B|X|Y|L1|R1|L2|R2|Start|Back
    Gui, 2:Add, Text, x205 yp, Arbitrary AutoHotkey v1 source
    Gui, 2:Add, Edit, x205 y+5 w480 h350 vActionEditor WantReturn WantTab HScroll
    Gui, 2:Add, Checkbox, x205 y+10 w300 vRepeatCurrent gRepeatChanged, Repeat raw key while held
    Gui, 2:Add, Text, x205 y+12, Repeat interval
    Gui, 2:Add, Slider, x300 yp-3 w250 vRepeatSlider gRepeatRateChanged Range20-200, 35
    Gui, 2:Add, Button, xm y+12 w100 gSaveAction, Save
    Gui, 2:Add, Button, x+10 yp w100 gTestAction, Test

    GuiControl, 2:, ActionList, A
    GuiControl, 2:, ActionEditor,
return

ShowActions:
    Gui, 2:Show, w720 h560, XInput Button Actions
return

ActionSelected:
    GuiControlGet, oldText, 2:, ActionEditor
    GuiControlGet, oldRepeat, 2:, RepeatCurrent
    ActionText[SelectedAction] := oldText
    ActionRepeat[SelectedAction] := oldRepeat ? 1 : 0
    SaveMapping(SelectedAction)

    GuiControlGet, SelectedAction, 2:, ActionList
    newText := ActionText[SelectedAction]
    newRepeat := ActionRepeat[SelectedAction]

    GuiControl, 2:, ActionEditor, %newText%
    GuiControl, 2:, RepeatCurrent, %newRepeat%
return

SaveAction:
    GuiControlGet, source, 2:, ActionEditor
    GuiControlGet, repeat, 2:, RepeatCurrent
    ActionText[SelectedAction] := source
    ActionRepeat[SelectedAction] := repeat ? 1 : 0
    SaveMapping(SelectedAction)
return

TestAction:
    Gosub, SaveAction
    RunAction(SelectedAction)
return

RepeatChanged:
    GuiControlGet, repeat, 2:, RepeatCurrent
    ActionRepeat[SelectedAction] := repeat ? 1 : 0
    SaveMapping(SelectedAction)
return

RepeatRateChanged:
    GuiControlGet, RepeatInterval, 2:, RepeatSlider
    SetTimer, RepeatHeldRawKeys, Off
    SetTimer, RepeatHeldRawKeys, %RepeatInterval%
return

2GuiClose:
2GuiEscape:
    Gui, 2:Hide
return

; ------------------------------------------------------------
; Run multiline source
; ------------------------------------------------------------

RunAction(name) {
    global ActionText

    source := ActionText[name]

    if (source = "")
        return

    dir := A_Temp "\XInputButtonActions"
    FileCreateDir, %dir%

    file := dir "\" name ".ahk"
    FileDelete, %file%
    FileAppend, %source%`r`n, %file%

    command := """" A_AhkPath """ """ file """"
    Run, %command%
}

; ------------------------------------------------------------
; Persistence
; ------------------------------------------------------------

LoadMappings() {
    global ActionText, ActionRepeat, MappingDirectory, RepeatFile

    FileCreateDir, %MappingDirectory%
    FileEncoding, UTF-8

    for name, unused in ActionText {
        file := MappingDirectory "\" name ".ahk"

        if (FileExist(file)) {
            FileRead, source, %file%
            ActionText[name] := source
        }

        IniRead, value, %RepeatFile%, Repeat, %name%, 0
        ActionRepeat[name] := value = "1" ? 1 : 0
    }
}

SaveMapping(name) {
    global ActionText, ActionRepeat, MappingDirectory, RepeatFile

    FileCreateDir, %MappingDirectory%
    FileEncoding, UTF-8

    file := MappingDirectory "\" name ".ahk"
    source := ActionText[name]

    FileDelete, %file%
    FileAppend, %source%, %file%
    IniWrite, % ActionRepeat[name], %RepeatFile%, Repeat, %name%
}

; ------------------------------------------------------------
; Controls and helpers
; ------------------------------------------------------------

SensitivityChanged:
    GuiControlGet, value,, SensitivitySlider
    Sensitivity := value / 10.0
return

DeadzoneChanged:
    GuiControlGet, Deadzone,, DeadzoneSlider
return

TriggerChanged:
    GuiControlGet, TriggerThreshold,, TriggerSlider
return

EnabledChanged:
    GuiControlGet, Enabled,, Enabled
return

TruncZero(value) {
    return value >= 0 ? Floor(value) : Ceil(value)
}

UpdateStatus(text) {
    GuiControl,, Status, %text%
}

GuiClose:
GuiEscape:
    ReleaseAllHeldRawKeys()
    SetTimer, PollXInput, Off
    SetTimer, RepeatHeldRawKeys, Off
    ExitApp
return
