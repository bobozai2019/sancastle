param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe')

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'probe_wave_packet.gd'
$output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --script $scriptPath 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Output $output
if ($code -ne 0 -or $output -notmatch 'PASS: W04 wave probe' -or
    $output -match 'SHADER ERROR|SCRIPT ERROR|ERROR:|FAIL:') {
    exit 1
}
exit 0
