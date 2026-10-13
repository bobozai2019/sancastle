param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe')

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'probe_sand_shape_gpu.gd'
$output = & $GodotExe --path $projectPath --rendering-driver d3d12 --script $scriptPath 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Output $output
if ($code -ne 0 -or $output -notmatch 'PASS: S01 GPU shape A/B' -or
    $output -match 'SCRIPT ERROR|SHADER ERROR|ERROR:|FAIL:') {
    exit 1
}
$evidence = Join-Path $projectPath 'test_output\sandcastle_visual_reconstruction_phase2\验收\S01_sand_shape_gpu_ab.json'
if (-not (Test-Path -LiteralPath $evidence)) { exit 1 }
exit 0
