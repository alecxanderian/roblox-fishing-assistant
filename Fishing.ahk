#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn
Persistent
SetWorkingDir A_ScriptDir
CoordMode 'Pixel', 'Screen'
CoordMode 'ToolTip', 'Screen'
SendMode 'Event'
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
global combatGapMs := Max(70, Integer(IniRead(settings, 'Combat', 'AttackIntervalMs', IniRead(settings, 'Combat', 'ClickIntervalMs', 120))))
global combatTimeoutMs := Integer(IniRead(settings, 'Combat', 'TimeoutMs', 45000))
global combatProbeMs := Integer(IniRead(settings, 'Combat', 'ReturnProbeMs', 6000))
global combatStarted := 0, lastAttack := 0, rodHeld := false, attackHeld := false, cancelHeld := false, lastDamageAt := 0
global healthAt := 0, previousHealth := -1, lastReelEnd := 0, rodLostAt := 0
global captureEncounters := A_Args.Length >= 2 && A_Args[2] = '--capture-encounters'
global historyEnabled := Integer(IniRead(settings, 'History', 'Enabled', 1))
global historyImages := Integer(IniRead(settings, 'History', 'IncludeRewardImage', 1))
global testRodLoss := A_Args.Length >= 3 && A_Args[3] = '--test-rod-loss'
global captureSequence := 0, historyGui := 0, historyList := 0
OnExit((*) => ReleaseAll())
SetTimer Tick, 15
ToolTip 'Fishing ready | F6 start/pause | F7 stop | F10 history', 20, 60
if A_Args.Length && A_Args[1] = '--check'
    ExitApp()
if historyEnabled
    SetTimer ResumeHistory, -500
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
F10::ShowHistory()
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
    global hwnd
    hwnd := WinActive('ahk_exe RobloxPlayerBeta.exe')
    if !hwnd
        return
    Toggle()
}

Log(msg) {
    global logPath
    try FileAppend FormatTime(, 'yyyy-MM-dd HH:mm:ss') ' | ' msg '`n', logPath
}
ResumeHistory() {
    helper := A_ScriptDir '\CatchLogger.ps1'
    if FileExist(helper) {
        command := '"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File "'
            . helper '" -ProcessPending'
        try Run command, A_ScriptDir, 'Hide'
    }
}
CaptureCatch() {
    global historyEnabled, historyImages, hwnd, captureSequence, reelStarted, maxProgress
    if !historyEnabled || !WinActive('ahk_id ' hwnd)
        return
    try {
        helper := A_ScriptDir '\CatchLogger.ps1'
        if !FileExist(helper) {
            Log('HISTORY helper missing: CatchLogger.ps1')
            return
        }
        g := Geometry()
        folder := A_ScriptDir '\catches'
        DirCreate folder
        captureSequence += 1
        id := A_NowUTC '-' Format('{:03}', A_MSec) '-' DllCall('GetCurrentProcessId') '-' captureSequence
        picture := folder '\' id '.bmp'
        ; Capture only the reward card, never the full screen or Discord monitor.
        SaveScreenBmp(picture, Round(g.x+g.w/2-210*g.s), Round(g.y+g.h*0.25),
            Round(420*g.s), Round(g.h*0.20))
        job := folder '\' id '.ini'
        IniWrite id, job, 'Catch', 'Id'
        IniWrite FormatTime(A_NowUTC, "yyyy-MM-dd'T'HH:mm:ss'Z'"), job, 'Catch', 'TimestampUtc'
        IniWrite FormatTime(, 'yyyy-MM-dd HH:mm:ss'), job, 'Catch', 'LocalTime'
        IniWrite picture, job, 'Catch', 'ImagePath'
        IniWrite Round(Max(0, A_TickCount-reelStarted-600)/1000, 2), job, 'Catch', 'ReelSeconds'
        IniWrite historyImages, job, 'Catch', 'IncludeImage'
        IniWrite Round(maxProgress*100), job, 'Catch', 'MaxProgress'
        IniWrite !Observe(g).panel && EnemyVisible(g), job, 'Catch', 'EncounterDetected'
        command := '"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File "'
            . helper '" -JobPath "' job '"'
        Run command, A_ScriptDir, 'Hide'
        Log('HISTORY reward queued: ' id)
    } catch as err {
        Log('HISTORY capture failed: ' err.Message ' at line ' err.Line)
    }
}
SaveScreenBmp(path, x, y, w, h) {
    screen := DllCall('GetDC', 'Ptr', 0, 'Ptr')
    memory := DllCall('gdi32\CreateCompatibleDC', 'Ptr', screen, 'Ptr')
    bitmap := 0, old := 0
    try {
        info := Buffer(40, 0)
        NumPut('UInt', 40, 'Int', w, 'Int', -h, 'UShort', 1, 'UShort', 32, info)
        bits := 0
        bitmap := DllCall('gdi32\CreateDIBSection', 'Ptr', screen, 'Ptr', info, 'UInt', 0,
            'Ptr*', &bits, 'Ptr', 0, 'UInt', 0, 'Ptr')
        if !bitmap || !bits
            throw Error('Could not allocate reward image')
        old := DllCall('gdi32\SelectObject', 'Ptr', memory, 'Ptr', bitmap, 'Ptr')
        if !DllCall('gdi32\BitBlt', 'Ptr', memory, 'Int', 0, 'Int', 0, 'Int', w, 'Int', h,
            'Ptr', screen, 'Int', x, 'Int', y, 'UInt', 0x40CC0020)
            throw Error('Could not capture reward image')
        header := Buffer(14, 0), size := w*h*4
        NumPut('UShort', 0x4D42, 'UInt', 54+size, header)
        NumPut('UInt', 54, header, 10)
        output := FileOpen(path, 'w')
        try {
            output.RawWrite(header)
            output.RawWrite(info)
            output.RawWrite(bits, size)
        } finally {
            output.Close()
        }
    } finally {
        if old
            DllCall('gdi32\SelectObject', 'Ptr', memory, 'Ptr', old)
        if bitmap
            DllCall('gdi32\DeleteObject', 'Ptr', bitmap)
        if memory
            DllCall('gdi32\DeleteDC', 'Ptr', memory)
        if screen
            DllCall('ReleaseDC', 'Ptr', 0, 'Ptr', screen)
    }
}
ShowHistory() {
    global historyGui, historyList
    if IsObject(historyGui)
        historyGui.Destroy()
    historyGui := Gui('+Resize', 'Fishing Catch History')
    historyGui.SetFont('s10', 'Segoe UI')
    historyGui.AddText('xm', 'Confirmed catches and encounters persist between sessions. Discord status appears below.')
    historyGui.AddButton('xm w100', 'Refresh').OnEvent('Click', (*) => RefreshHistory())
    historyList := historyGui.AddListView('xm w920 r18 Grid', ['Time', 'Catch', 'Weight', 'Type', 'Discord', 'Reel (s)'])
    historyGui.OnEvent('Size', (gui, minmax, width, height) => historyList.Move(, , Max(500, width-30), Max(150, height-95)))
    RefreshHistory()
    historyGui.Show()
}
RefreshHistory() {
    global historyList
    historyList.Delete()
    path := A_ScriptDir '\CatchHistory.tsv'
    if FileExist(path) {
        try {
            lines := StrSplit(RTrim(FileRead(path, 'UTF-8'), '`r`n'), '`n', '`r')
            Loop lines.Length {
                index := lines.Length-A_Index+1
                if index <= 1
                    break
                fields := StrSplit(lines[index], '`t')
                if fields.Length >= 6
                    historyList.Add('', fields[1], fields[2], fields[3], fields[4], fields[5], fields[6])
            }
        }
    }
    Loop 6
        historyList.ModifyCol(A_Index, 'AutoHdr')
}
Release() {
    global held
    if held {
        SendEvent '{e up}'
        held := false
    }
}
ReleaseAll() {
    Release()
    ReleaseAttack()
    ReleaseCancel()
    ReleaseRod()
}
ReleaseRod() {
    global rodHeld
    if rodHeld {
        SendEvent '{9 up}'
        rodHeld := false
    }
}
ReleaseAttack() {
    global attackHeld
    if attackHeld {
        SendEvent '{t up}'
        attackHeld := false
    }
}
AttackPulse() {
    global attackHeld, lastAttack, hwnd
    if !WinActive('ahk_id ' hwnd)
        return
    SendEvent '{t down}'
    attackHeld := true
    lastAttack := A_TickCount
    SetTimer ReleaseAttack, -40
}
EquipRod() {
    global rodHeld, hwnd
    if !WinActive('ahk_id ' hwnd)
        return
    Release()
    ReleaseAttack()
    SendEvent '{9 down}'
    rodHeld := true
    Log('ROD equipping with keyboard slot 9')
    SetPhase('Equipping rod')
}
CheckRod(reason) {
    global combatStarted, rodLostAt
    ReleaseAll()
    combatStarted := A_TickCount
    rodLostAt := 0
    Log('ROD checking: ' reason)
    SetPhase('Checking rod')
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
    Log('COMBAT ' reason '; artifact volley on T; no mouse input')
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
EncounterVisible(g) {
    if EnemyVisible(g)
        return true
    ; Enemy introductions have red titles in the central reward card.
    mid := g.x+g.w/2
    return FindColor(&ex, &ey, mid-180*g.s, g.y+g.h*0.27,
        mid+180*g.s, g.y+g.h*0.35, 0xD95040, 30)
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
    global running, hwnd, floatBase, lostAt, combatStarted
    if running {
        Stop('Paused')
        return
    }
    hwnd := WinActive('ahk_exe RobloxPlayerBeta.exe')
    if !hwnd {
        ToolTip 'Focus Roblox, then press F6.', 20, 60
        return
    }
    running := true, floatBase := 0, lostAt := 0, combatStarted := A_TickCount
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
    SendEvent '{e down}'
    held := true, lastClick := A_TickCount
    SetTimer Release, -Max(10, durationMs ? durationMs : pulseMs)
}
Tick() {
    global running, phase, hwnd, since, held, floatBase, lostAt, detail
    global lastClick, gapMs, slackTarget, castTarget, repeatCast, catches, stopAfter
    global previousMarker
    global maxProgress, reelStarted, markerAt
    global combatStarted, lastAttack, combatGapMs, combatTimeoutMs, combatProbeMs, rodHeld, attackHeld
    global healthAt, previousHealth, lastReelEnd, lastDamageAt, rodLostAt, testRodLoss
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
        ; Live regression test: reproduce the rod being put away while waiting.
        if testRodLoss && phase = 'Waiting for bite' && o.panel && elapsed >= 700 {
            testRodLoss := false
            SendEvent '{9 down}'
            rodHeld := true
            SetTimer ReleaseRod, -100
            Log('TEST putting rod away during bite wait to verify automatic recovery')
            return
        }
        inCombat := phase = 'Combat' || phase = 'Equipping rod'
            || phase = 'Checking rod' || phase = 'Checking fishing return' || phase = 'Waiting for combat clear'
        if inCombat && A_TickCount-combatStarted >= combatTimeoutMs {
            Stop(phase = 'Combat' ? 'Combat recovery timed out; check player'
                : 'Rod recovery timed out; check position and rod slot 9')
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
        watchRod := phase = 'Ready to cast' || phase = 'Casting' || phase = 'Cast settling'
            || phase = 'Waiting for bite' || phase = 'Hooking'
        if o.panel
            rodLostAt := 0
        else if watchRod {
            Release()
            if !rodLostAt
                rodLostAt := A_TickCount
            detail := 'Fishing panel lost; checking rod availability'
            if A_TickCount-rodLostAt >= 650 {
                if EncounterVisible(g)
                    BeginCombat(false, 'enemy detected after fishing panel disappeared')
                else
                    CheckRod('fishing panel disappeared during ' phase)
            }
            ShowTip()
            return
        }
        if phase = 'Detecting' {
            if o.blue
                SetPhase('Reeling')
            else if o.gold
                SetPhase('Ready to cast')
            else if o.red {
                floatBase := o.redY
                SetPhase('Waiting for bite')
            } else if elapsed > 500
                CheckRod('start or resume fishing')
        } else if phase = 'Checking rod' {
            if o.panel {
                Log('ROD confirmed out; fishing panel present')
                SetPhase('Detecting')
            } else if EncounterVisible(g) {
                BeginCombat(false, 'enemy detected during rod check')
            } else if elapsed >= 300
                EquipRod()
        } else if phase = 'Ready to cast' {
            if !o.gold {
                SetPhase('Detecting')
            } else {
                ; E is supported by the minigame and preserves the mounted state.
                SendEvent '{e down}'
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
                    ; Longer E pulses increase time spent reeling. Predict only
                    ; the next 30 ms, releasing at the blue-zone limit.
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
                    SetTimer CaptureCatch, -20
                }
            }
            if elapsed > 90000
                Stop('Reel timed out')
        } else if phase = 'Catch finished' {
            if !o.panel && elapsed > 500 && EncounterVisible(g) {
                BeginCombat(false, 'enemy detected after catch')
                return
            }
            ; Wait out the Landed message before the next cast.
            if elapsed > 2400 {
                if repeatCast
                    CheckRod('after catch')
                else
                    Stop('Single catch finished')
            }
        } else if phase = 'Combat' {
            detail := 'Artifact volley: T | restore rod: 9 | keyboard only'
            if A_TickCount-combatStarted >= combatTimeoutMs {
                Stop('Combat recovery timed out; check player')
            } else if o.panel && elapsed >= 1000 {
                ReleaseAll()
                CheckRod('after combat; fishing panel restored')
            } else if elapsed >= combatProbeMs && !EnemyVisible(g) {
                ReleaseAttack()
                SetPhase('Waiting for combat clear')
            } else if A_TickCount-lastAttack >= combatGapMs && !attackHeld {
                AttackPulse()
            }
        } else if phase = 'Equipping rod' {
            if elapsed >= 100 {
                ReleaseRod()
                SetPhase('Checking fishing return')
            }
        } else if phase = 'Checking fishing return' {
            if o.panel {
                Log('ROD confirmed out after equipping slot 9')
                SetPhase('Detecting')
            } else if EncounterVisible(g) || lastDamageAt > since {
                SetPhase('Combat')
            } else if elapsed >= 1200
                SetPhase('Waiting for combat clear')
        } else if phase = 'Waiting for combat clear' {
            detail := 'Volley paused to clear combat lock; retrying rod slot 9'
            if o.panel {
                CheckRod('after combat lock cleared')
            } else if EncounterVisible(g) || lastDamageAt > since {
                Log('COMBAT damage during quiet period; resuming attacks')
                SetPhase('Combat')
            } else if elapsed >= 2000 {
                EquipRod()
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
    ToolTip 'Fishing | ' phase '`n' detail '`nF6 start/pause | F7 stop | F8 inspect | F10 history | Ctrl+Alt+Esc exit`nCompleted reel cycles: ' catches, 20, 60
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
