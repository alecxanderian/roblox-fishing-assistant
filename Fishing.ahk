#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn
Persistent
SetWorkingDir A_ScriptDir
CoordMode 'Pixel', 'Screen'
CoordMode 'Mouse', 'Screen'
CoordMode 'ToolTip', 'Screen'
SendMode 'Event'
SetMouseDelay -1
SetKeyDelay -1

; Coordinates scale from the supplied 1920 x 1008 client recording.
global running := false, phase := 'Stopped', held := false, hwnd := 0
global since := 0, lastClick := 0, floatBase := 0, lostAt := 0
global lastTip := 0, detail := '', catches := 0, previousMarker := -1
global logPath := A_ScriptDir '\Fishing.log'
global settings := A_ScriptDir '\Fishing.ini'
global pulseMs := Integer(IniRead(settings, 'Control', 'PulseMs', 32))
global gapMs := Integer(IniRead(settings, 'Control', 'MinimumGapMs', 65))
global slackTarget := Float(IniRead(settings, 'Control', 'SlackTarget', 0.045))
global castTarget := Float(IniRead(settings, 'Control', 'CastTarget', 0.93))
global repeatCast := Integer(IniRead(settings, 'Control', 'Repeat', 1))
global stopAfter := 0
global maxProgress := 0
OnExit((*) => Release())
SetTimer Tick, 15
ToolTip 'Fishing ready | F6 start/pause | F7 stop | F8 inspect', 20, 60
if A_Args.Length && A_Args[1] = '--check'
    ExitApp()
if A_Args.Length && A_Args[1] = '--test' {
    stopAfter := A_TickCount + 35000
    if WinExist('ahk_exe RobloxPlayerBeta.exe') {
        WinActivate 'ahk_exe RobloxPlayerBeta.exe'
        SetTimer BeginTest, -700
    }
}

F6::Toggle()
F7::Stop('Stopped by F7')
F8::Inspect()
^!Esc::ExitApp()

BeginTest() {
    global hwnd
    hwnd := WinActive('ahk_exe RobloxPlayerBeta.exe')
    if !hwnd
        return
    o := Observe(Geometry())
    if !o.gold && !o.blue && !o.red {
        SendEvent '{e down}'
        Sleep 1000
        SendEvent '{e up}'
        Sleep 700
    }
    Toggle()
}

Log(msg) {
    global logPath
    try FileAppend FormatTime(, 'yyyy-MM-dd HH:mm:ss') ' | ' msg '`n', logPath
}
Release() {
    global held
    if held {
        SendEvent '{LButton up}'
        held := false
    }
}
SetPhase(name) {
    global phase, since, detail, previousMarker, maxProgress
    phase := name, since := A_TickCount, detail := '', previousMarker := -1
    if name = 'Reeling'
        maxProgress := 0
    Log('STATE ' name)
}
Stop(reason := 'Stopped') {
    global running
    running := false
    Release()
    SetPhase(reason)
    ShowTip(true)
}
Toggle() {
    global running, hwnd, floatBase, lostAt
    if running {
        Stop('Paused')
        return
    }
    hwnd := WinActive('ahk_exe RobloxPlayerBeta.exe')
    if !hwnd {
        ToolTip 'Focus Roblox, then press F6.', 20, 60
        return
    }
    running := true, floatBase := 0, lostAt := 0
    SetPhase('Detecting')
}
Geometry() {
    global hwnd
    WinGetClientPos &cx, &cy, &cw, &ch, 'ahk_id ' hwnd
    ; Roblox UI in this recording uses a centered panel anchored to the bottom.
    scale := Min(cw / 1920, ch / 1008)
    return {x: cx, y: cy, w: cw, h: ch, s: scale,
        left: Round(cx + cw/2 - 208*scale), right: Round(cx + cw/2 + 208*scale),
        top: Round(cy + ch - 222*scale), bottom: Round(cy + ch - 164*scale)}
}
FindColor(&px, &py, x1, y1, x2, y2, color, tolerance := 15) {
    return PixelSearch(&px, &py, Round(x1), Round(y1), Round(x2), Round(y2), color, tolerance)
}
Observe(g) {
    s := g.s, span := g.right-g.left
    ; Require the red fishing icon; terrain can contain gold/blue lookalikes.
    panel := FindColor(&ix, &iy, g.left-15*s, g.y+g.h-252*s,
        g.left+17*s, g.y+g.h-222*s, 0xBB4338, 35)
    if !panel
        return {blue: false, gold: false, marker: -1, red: false, redY: 0, row: 0, progress: 0, under: false}
    blue := FindColor(&bx, &by, g.left+7*s, g.top, g.left+25*s, g.bottom, 0x535E6B, 12)
    gold := FindColor(&gx, &gy, g.right-48*s, g.top, g.right-6*s, g.bottom, 0xA38E55, 19)
    marker := -1, row := 0
    if blue || gold {
        row := (blue ? by : gy) + Round(4*s)
        if FindColor(&mx, &my, g.left-3*s, row, g.right+3*s, row+2*s, 0xE9E4D8, 23)
            marker := (mx-g.left)/span
        else if gold && FindColor(&mx, &my, g.left-3*s, row, g.right+3*s, row+2*s, 0xD6BC77, 25)
            marker := (mx-g.left)/span
    }
    ; Red float is normally above its baseline and dips when a fish bites.
    mid := g.x + g.w/2
    red := FindColor(&rx, &ry, mid-10*s, g.top, mid+10*s, g.bottom, 0xCE4F54, 35)
    if !red
        ry := 0
    under := !blue && !gold && FindColor(&ux, &uy, mid-32*s,
        g.y+g.h-172*s, mid+32*s, g.y+g.h-156*s, 0xD45550, 32)
    progress := 0
    if blue && FindColor(&px, &py, g.right, row+22*s, g.left, row+39*s, 0x78AE99, 23)
        progress := Max(0, Min(1, (px-g.left)/span))
    return {blue: blue, gold: gold, marker: marker, red: red, redY: ry, row: row, progress: progress, under: under}
}
Pulse() {
    global held, lastClick, pulseMs
    if !WinActive('ahk_exe RobloxPlayerBeta.exe')
        return
    SendEvent '{LButton down}'
    held := true, lastClick := A_TickCount
    SetTimer Release, -Max(10, pulseMs)
}
Tick() {
    global running, phase, hwnd, since, held, floatBase, lostAt, detail
    global lastClick, gapMs, slackTarget, castTarget, repeatCast, catches, stopAfter
    global previousMarker
    global maxProgress
    if stopAfter && A_TickCount >= stopAfter {
        Stop('Test finished')
        ExitApp()
    }
    if !running
        return
    if !WinActive('ahk_id ' hwnd) {
        Stop('Paused: Roblox lost focus')
        return
    }
    try {
        g := Geometry(), o := Observe(g), elapsed := A_TickCount-since
        detail := Format('Marker: {} | blue {} | gold {} | float Y {}',
            o.marker < 0 ? '?' : Round(o.marker*100) '%', o.blue, o.gold, o.redY)
        if phase = 'Detecting' {
            if o.blue
                SetPhase('Reeling')
            else if o.gold
                SetPhase('Ready to cast')
            else if o.red {
                floatBase := o.redY
                SetPhase('Waiting for bite')
            } else if elapsed > 5000
                Stop('Fishing panel not found: open it with E, then F6')
        } else if phase = 'Ready to cast' {
            if !o.gold {
                SetPhase('Detecting')
            } else {
                ; A fixed, unobstructed point in the water, away from panel buttons.
                MouseMove Round(g.x+g.w*0.60), Round(g.y+g.h*0.50), 0
                SendEvent '{LButton down}'
                held := true
                SetPhase('Casting')
            }
        } else if phase = 'Casting' {
            if o.marker >= castTarget {
                Release()
                Log('CAST release at ' Round(o.marker*100, 1) '%')
                floatBase := 0
                SetPhase('Cast settling')
            } else if elapsed > 5000
                Stop('Cast timed out: inspect with F8')
        } else if phase = 'Cast settling' {
            if elapsed > 600 && o.red && !o.gold {
                floatBase := o.redY
                SetPhase('Waiting for bite')
            } else if elapsed > 5000
                SetPhase('Detecting')
        } else if phase = 'Waiting for bite' {
            if o.blue {
                SetPhase('Reeling')
            } else if o.under {
                Pulse()
                Log('HOOK red under alert')
                SetPhase('Hooking')
            } else if o.red {
                if !floatBase
                    floatBase := o.redY
                floatBase := Min(floatBase, o.redY)
                if o.redY-floatBase >= Max(8, Round(10*g.s)) {
                    Pulse()
                    Log('HOOK dip ' (o.redY-floatBase) 'px')
                    SetPhase('Hooking')
                }
            }
            if elapsed > 45000
                Stop('Bite timed out: inspect with F8')
        } else if phase = 'Hooking' {
            if o.blue
                SetPhase('Reeling')
            else if elapsed > 1600
                SetPhase('Detecting')
        } else if phase = 'Reeling' {
            if o.blue {
                lostAt := 0
                maxProgress := Max(maxProgress, o.progress)
                detail .= ' | progress ' Round(o.progress*100) '%'
                if o.marker >= 0 {
                    ; Clicks raise tension. Release early if the marker is rising.
                    rising := previousMarker >= 0 ? Max(0, o.marker-previousMarker) : 0
                    predicted := o.marker + rising*2
                    if predicted < slackTarget && !held && A_TickCount-lastClick >= gapMs
                        Pulse()
                    previousMarker := o.marker
                } else
                    Release()
            } else {
                Release()
                if !lostAt
                    lostAt := A_TickCount
                if A_TickCount-lostAt > 600 {
                    catches += 1
                    Log('REEL ended; maximum green progress=' Round(maxProgress*100) '%')
                    SetPhase('Catch finished')
                }
            }
            if elapsed > 90000
                Stop('Reel timed out')
        } else if phase = 'Catch finished' {
            ; Wait out the Landed message before the next cast.
            if elapsed > 2400 {
                if repeatCast
                    SetPhase('Detecting')
                else
                    Stop('Single catch finished')
            }
        }
        ShowTip()
    } catch as err {
        Stop('Error: ' err.Message)
        Log(err.Message ' at line ' err.Line)
    }
}
ShowTip(force := false) {
    global phase, detail, lastTip, catches
    if !force && A_TickCount-lastTip < 150
        return
    lastTip := A_TickCount
    ToolTip 'Fishing | ' phase '`n' detail '`nF6 start/pause | F7 stop | F8 inspect | Ctrl+Alt+Esc exit`nCompleted reel cycles: ' catches, 20, 60
}
Inspect() {
    global hwnd, detail
    hwnd := WinActive('ahk_exe RobloxPlayerBeta.exe')
    if !hwnd
        return
    try {
        g := Geometry(), o := Observe(g)
        detail := 'Client ' g.w 'x' g.h ' | scan ' g.left ',' g.top ' to ' g.right ',' g.bottom
        detail .= '`nblue=' o.blue ' gold=' o.gold ' marker=' o.marker ' floatY=' o.redY
        Log('INSPECT ' StrReplace(detail, '`n', ' | '))
        ShowTip(true)
    }
}
