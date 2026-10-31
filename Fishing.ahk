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
global pulseMs := Integer(IniRead(settings, 'Control', 'PulseMs', 75))
global gapMs := Integer(IniRead(settings, 'Control', 'MinimumGapMs', 90))
global slackTarget := Float(IniRead(settings, 'Control', 'SlackTarget', 0.065))
global castTarget := Float(IniRead(settings, 'Control', 'CastTarget', 0.93))
global repeatCast := Integer(IniRead(settings, 'Control', 'Repeat', 1))
global stopAfter := 0
global maxProgress := 0, reelStarted := 0, markerAt := 0
global combatEnabled := Integer(IniRead(settings, 'Combat', 'Enabled', 1))
global combatGapMs := Max(70, Integer(IniRead(settings, 'Combat', 'ClickIntervalMs', 120)))
global combatTimeoutMs := Integer(IniRead(settings, 'Combat', 'TimeoutMs', 45000))
global combatProbeMs := Integer(IniRead(settings, 'Combat', 'ReturnProbeMs', 6000))
global combatStarted := 0, lastAttack := 0, interactHeld := false, cancelHeld := false, lastDamageAt := 0
global healthAt := 0, previousHealth := -1, lastReelEnd := 0
global captureEncounters := A_Args.Length >= 2 && A_Args[2] = '--capture-encounters'
OnExit((*) => ReleaseAll())
SetTimer Tick, 15
ToolTip 'Fishing ready | F6 start/pause | F7 stop | F8 inspect', 20, 60
if A_Args.Length && A_Args[1] = '--check'
    ExitApp()
if A_Args.Length && (A_Args[1] = '--test' || A_Args[1] = '--run') {
    if A_Args[1] = '--test' {
        testSeconds := A_Args.Length >= 2 ? Max(5, Min(900, Integer(A_Args[2]))) : 35
        stopAfter := A_TickCount + testSeconds*1000
        Log('TEST starting for ' testSeconds ' seconds; PID=' DllCall('GetCurrentProcessId'))
    } else
        Log('RUN starting; PID=' DllCall('GetCurrentProcessId'))
    if WinExist('ahk_exe RobloxPlayerBeta.exe') {
        WinActivate 'ahk_exe RobloxPlayerBeta.exe'
        SetTimer BeginTest, -700
    }
}

F6::Toggle()
F7::Stop('Stopped by F7')
F8::Inspect()
F9::ManualCombat()
^!Esc::ExitApp()

ManualCombat() {
    global running, hwnd
    hwnd := WinActive('ahk_exe RobloxPlayerBeta.exe')
    if !hwnd
        return
    running := true
    Log('MANUAL combat recovery requested')
    BeginCombat(Observe(Geometry()).panel, 'manual recovery')
}

BeginTest() {
    global hwnd, combatStarted
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
    if !Observe(Geometry()).panel {
        combatStarted := A_TickCount
        SetPhase('Waiting for combat clear')
    }
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
ReleaseAll() {
    global interactHeld
    Release()
    ReleaseCancel()
    if interactHeld {
        SendEvent '{e up}'
        interactHeld := false
    }
}
ReleaseCancel() {
    global cancelHeld
    if cancelHeld {
        SendEvent '{q up}'
        cancelHeld := false
    }
}
BeginCombat(closePanel := false, reason := 'fishing panel closed after reel') {
    global combatStarted, lastAttack, combatEnabled, cancelHeld, captureEncounters
    ReleaseAll()
    if !combatEnabled {
        Stop('Fishing interrupted after catch; combat recovery disabled')
        return
    }
    combatStarted := A_TickCount
    ; Optional live-reference mode leaves one second to capture a rare spawn.
    lastAttack := captureEncounters ? A_TickCount+1200 : 0
    if closePanel {
        SendEvent '{q down}'
        cancelHeld := true
        SetTimer ReleaseCancel, -100
    }
    Log('COMBAT ' reason '; attacking and checking for return')
    SetPhase('Combat')
}
ReadHealth(g) {
    ; Sample the red player-health fill, excluding labels and other HUD bars.
    if FindColor(&hx, &hy, g.x+381*g.s, g.y+g.h-95*g.s,
        g.x+64*g.s, g.y+g.h-78*g.s, 0xB73536, 32)
        return Max(0, Min(1, (hx-g.x-64*g.s)/(317*g.s)))
    return -1
}
EnemyVisible(g) {
    ; River Snapper reference: red target-health fill below the compass.
    mid := g.x+g.w/2
    return FindColor(&ex, &ey, mid-182*g.s, g.y+150*g.s,
        mid+182*g.s, g.y+166*g.s, 0xD84D44, 30)
}
SetPhase(name) {
    global phase, since, detail, previousMarker, maxProgress, reelStarted, markerAt, lostAt
    phase := name, since := A_TickCount, detail := '', previousMarker := -1
    if name = 'Reeling'
        maxProgress := 0, reelStarted := A_TickCount, markerAt := 0, lostAt := 0
    Log('STATE ' name)
}
Stop(reason := 'Stopped') {
    global running
    running := false
    ReleaseAll()
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
        return {panel: false, blue: false, gold: false, marker: -1, red: false, redY: 0, row: 0, progress: 0, under: false}
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
    return {panel: true, blue: blue, gold: gold, marker: marker, red: red, redY: ry, row: row, progress: progress, under: under}
}
Pulse(durationMs := 0) {
    global held, lastClick, pulseMs
    if !WinActive('ahk_exe RobloxPlayerBeta.exe')
        return
    SendEvent '{LButton down}'
    held := true, lastClick := A_TickCount
    SetTimer Release, -Max(10, durationMs ? durationMs : pulseMs)
}
Tick() {
    global running, phase, hwnd, since, held, floatBase, lostAt, detail
    global lastClick, gapMs, slackTarget, castTarget, repeatCast, catches, stopAfter
    global previousMarker
    global maxProgress, reelStarted, markerAt
    global combatStarted, lastAttack, combatGapMs, combatTimeoutMs, combatProbeMs, interactHeld
    global healthAt, previousHealth, lastReelEnd, lastDamageAt
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
        inCombat := phase = 'Combat' || phase = 'Reopening fishing'
            || phase = 'Checking fishing return' || phase = 'Waiting for combat clear'
        if inCombat && A_TickCount-combatStarted >= combatTimeoutMs {
            Stop('Combat recovery timed out; check player')
            return
        }
        if A_TickCount-healthAt >= 500 {
            healthAt := A_TickCount
            health := ReadHealth(g)
            if health >= 0 {
                damage := previousHealth >= 0 ? previousHealth-health : 0
                if damage >= 0.01
                    lastDamageAt := A_TickCount
                if phase = 'Combat'
                    previousHealth := health
                else
                    previousHealth := Max(previousHealth, health)
                if inCombat && phase != 'Combat' && damage >= 0.01 {
                    ReleaseAll()
                    Log('COMBAT damage while waiting for return; resuming attacks')
                    SetPhase('Combat')
                    return
                }
                if damage >= 0.015 && catches > 0 && !inCombat {
                    Log('DAMAGE health fill dropped ' Round(damage*100, 1) '%')
                    BeginCombat(o.panel, 'health loss detected')
                    return
                }
            }
        }
        detail := Format('Marker: {} | blue {} | gold {} | float Y {}',
            o.marker < 0 ? '?' : Round(o.marker*100) '%', o.blue, o.gold, o.redY)
        if phase = 'Detecting' {
            if !o.panel && lastReelEnd && A_TickCount-lastReelEnd < 20000 && elapsed > 500 {
                BeginCombat()
                return
            }
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
                    ; Longer pulses increase time spent reeling. Predict only the
                    ; next 30 ms, and cut a pulse short at the blue-zone limit.
                    rising := previousMarker >= 0 ? Max(0, o.marker-previousMarker) : 0
                    sampleMs := markerAt ? Max(15, A_TickCount-markerAt) : 30
                    predicted := o.marker + rising*30/sampleMs
                    if held && predicted >= slackTarget
                        Release()
                    if predicted < slackTarget && !held && A_TickCount-lastClick >= gapMs
                        Pulse()
                    previousMarker := o.marker
                    markerAt := A_TickCount
                } else
                    Release()
            } else {
                Release()
                if !lostAt
                    lostAt := A_TickCount
                if A_TickCount-lostAt > 600 {
                    catches += 1
                    lastReelEnd := A_TickCount
                    Log('REEL ended; maximum green progress=' Round(maxProgress*100)
                        '%; duration=' Round(Max(0, A_TickCount-reelStarted-600)/1000, 2) 's')
                    SetPhase('Catch finished')
                }
            }
            if elapsed > 90000
                Stop('Reel timed out')
        } else if phase = 'Catch finished' {
            if !o.panel && elapsed > 500 {
                BeginCombat()
                return
            }
            ; Wait out the Landed message before the next cast.
            if elapsed > 2400 {
                if repeatCast
                    SetPhase('Detecting')
                else
                    Stop('Single catch finished')
            }
        } else if phase = 'Combat' {
            detail := 'Attacking | checking fishing return every ' Round(combatProbeMs/1000) 's'
            if A_TickCount-combatStarted >= combatTimeoutMs {
                Stop('Combat recovery timed out; check player')
            } else if o.panel && elapsed >= 1000 {
                ReleaseAll()
                Log('COMBAT fishing panel restored')
                SetPhase('Detecting')
            } else if elapsed >= combatProbeMs && !EnemyVisible(g) {
                Release()
                SetPhase('Waiting for combat clear')
            } else if A_TickCount-lastAttack >= combatGapMs && !held {
                Pulse(25)
                lastAttack := A_TickCount
            }
        } else if phase = 'Reopening fishing' {
            if elapsed >= 1000 {
                SendEvent '{e up}'
                interactHeld := false
                SetPhase('Checking fishing return')
            }
        } else if phase = 'Checking fishing return' {
            if o.panel {
                Log('COMBAT return confirmed by fishing panel')
                SetPhase('Detecting')
            } else if EnemyVisible(g) || lastDamageAt > since {
                SetPhase('Combat')
            } else if elapsed >= 700
                SetPhase('Waiting for combat clear')
        } else if phase = 'Waiting for combat clear' {
            detail := 'Attack paused to clear combat lock; retrying held E'
            if o.panel {
                Log('COMBAT return confirmed after combat lock cleared')
                SetPhase('Detecting')
            } else if EnemyVisible(g) || lastDamageAt > since {
                Log('COMBAT damage during quiet period; resuming attacks')
                SetPhase('Combat')
            } else if elapsed >= 2000 {
                SendEvent '{e down}'
                interactHeld := true
                SetPhase('Reopening fishing')
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
