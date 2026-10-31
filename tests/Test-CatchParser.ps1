$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'CatchLogger.ps1'
$tokens = $null
$parseErrors = $null
$tree = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'CatchLogger.ps1 has syntax errors' }
$function = $tree.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Parse-Reward'}, $true)
. ([scriptblock]::Create($function.Extent.Text))
$cases = @(
    @{Lines=@('Reeves Shad','1.7 jin - a new record','+52 angler xp');Type='Fish';Name='Reeves Shad';Weight='1.7 jin'},
    @{Lines=@('Grass Carp','2.1 jin','+16 angler xp');Type='Fish';Name='Grass Carp';Weight='2.1 jin'},
    @{Lines=@('Mandarin Fish','2,0 JIN','+28 angler xp');Type='Fish';Name='Mandarin Fish';Weight='2.0 jin'},
    @{Lines=@('Snakehead','+28 angler xp');Type='Catch';Name='Snakehead';Weight='Not read'},
    @{Lines=@('Iron-Shell Snapper','The water heaves. A snapper comes up after you!');Type='Encounter';Name='River Snapper';Weight=''},
    @{Lines=@('Hold to swing back','Let go in the gold');Type='Unreadable';Name='Reward not confidently read';Weight=''}
)
foreach ($case in $cases) {
    $actual = Parse-Reward $case.Lines
    foreach ($field in @('Type','Name','Weight')) {
        if ($actual[$field] -cne $case[$field]) { throw ('Unexpected '+$field+' for '+$case.Name+': '+$actual[$field]) }
    }
}
Write-Output ($cases.Count.ToString()+' reward parser checks passed.')
