$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'Fishing.ahk') -Raw
if ($source -match '(?i)\b(LButton|RButton|MButton|MouseMove|MouseClick|mouse_event)\b' -or
    $source -match '(?im)^\s*Click\b|\bClick\s*\(') {
    throw 'Mounted profile must not contain mouse input commands'
}
$expected = @('SendEvent ''{e down}''', 'SendEvent ''{e up}''',
    'SendEvent ''{t down}''', 'SendEvent ''{t up}''',
    'SendEvent ''{'' rodKey '' down}''', 'SendEvent ''{'' rodKey '' up}''')
foreach ($input in $expected) {
    if (-not $source.Contains($input)) { throw ('Missing required keyboard input: '+$input) }
}
Write-Output 'Keyboard-only input checks passed (E fishing, T volley, configurable rod key).'
