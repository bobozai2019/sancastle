param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe',
    [ValidateSet('W05_wave_foam_sequence.avi','W06_water_sequence.avi')]
    [string]$ArtifactName = 'W05_wave_foam_sequence.avi')

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'record_water_foam.gd'
$moviePath = Join-Path $projectPath ('test_output\sandcastle_visual_reconstruction_phase2\验收\' + $ArtifactName)
if (Test-Path -LiteralPath $moviePath) {
    Remove-Item -LiteralPath $moviePath
}
$output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --fixed-fps 30 --disable-vsync --write-movie $moviePath --script $scriptPath 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Output $output
if ($code -ne 0 -or $output -notmatch 'PASS: W05 foam movie' -or
    $output -match 'SHADER ERROR|SCRIPT ERROR|ERROR:|FAIL:' -or
    -not (Test-Path -LiteralPath $moviePath) -or
    (Get-Item -LiteralPath $moviePath).Length -lt 1000000) {
    exit 1
}
Write-Output ("MOVIE_BYTES=" + (Get-Item -LiteralPath $moviePath).Length)
exit 0
