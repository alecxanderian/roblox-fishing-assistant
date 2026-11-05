$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'Fishing.ahk') -Raw
$functions = foreach ($name in @('UpdateReelProgress', 'ReelTimeoutReason')) {
    $match = [regex]::Match($source, ('(?ms)^'+$name+'\([^\r\n]*\) \{.*?^\}'))
    if (-not $match.Success) { throw ('Missing timing function: '+$name) }
    $match.Value
}
$checks = @'
Assert(ok, message) {
    if !ok
        throw Error(message)
}
try {
    watch := {startedAt: 0, lastProgressAt: 0, checkpoint: 0}
    Loop 15 {
        now := A_Index*30000
        UpdateReelProgress(watch, A_Index*0.04, now)
        Assert(ReelTimeoutReason(watch, now, 120000, 600000) = '', 'A progressing long fight stopped')
    }
    Assert(watch.lastProgressAt = 450000, 'Progress did not refresh the stall clock')
    UpdateReelProgress(watch, 0.1, 500000)
    Assert(watch.lastProgressAt = 450000, 'Regressing progress refreshed the stall clock')
    Assert(ReelTimeoutReason(watch, 569999, 120000, 600000) = '', 'Stall timeout fired early')
    Assert(InStr(ReelTimeoutReason(watch, 570000, 120000, 600000), 'stalled'), 'A stalled fight did not stop')
    UpdateReelProgress(watch, 0.8, 600000)
    Assert(InStr(ReelTimeoutReason(watch, 600000, 120000, 600000), 'maximum'), 'Maximum duration did not stop a progressing fight')
    watch := {startedAt: 1000000, lastProgressAt: 1000000, checkpoint: 0}
    Loop 20
        UpdateReelProgress(watch, A_Index*0.001, 1000000+A_Index*100)
    Assert(watch.lastProgressAt > 1000000, 'Small progress steps never refreshed the clock')
    Assert(ReelTimeoutReason(watch, 1003000, 120000, 600000) = '', 'A fresh catch inherited an old timeout')
    FileAppend 'Fishing timing checks passed: long progress, stalls, maximum, small steps, fresh catch.`n', '*'
    ExitApp 0
} catch as err {
    FileAppend err.Message '`n', '**'
    ExitApp 1
}
'@
$testDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools'
[void][IO.Directory]::CreateDirectory($testDirectory)
$temporary = Join-Path $testDirectory ('fishing-timing-'+[guid]::NewGuid().ToString('N')+'.ahk')
try {
    Set-Content -LiteralPath $temporary -Encoding UTF8 -Value ("#Requires AutoHotkey v2.0`n"+($functions -join "`n")+"`n"+$checks)
    & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut $temporary | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Fishing timing checks failed' }
} finally {
    Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue
}
