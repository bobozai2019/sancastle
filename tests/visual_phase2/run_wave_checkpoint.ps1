param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe',
    [int]$TargetTick = 60)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'probe_wave_checkpoint.gd'
$output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --script $scriptPath -- "--target-tick=$TargetTick" 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Output $output
if ($code -ne 0 -or $output -notmatch 'PASS: W04 checkpoint' -or
    $output -match 'SHADER ERROR|SCRIPT ERROR|ERROR:|FAIL:') {
    exit 1
}
exit 0
