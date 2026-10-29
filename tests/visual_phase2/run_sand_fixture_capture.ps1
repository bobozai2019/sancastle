param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe',
    [ValidateSet('oblique','close','grazing')][string]$Camera = 'oblique',
    [ValidateSet(1,2)][int]$Subdivision = 2,
    [ValidateSet('all','no_grain','no_normal','no_wet','no_compaction')]
    [string]$Component = 'all',
    [ValidateSet('','dry','wet','retreat','dried')][string]$Stage = '')

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'capture_sand_fixture.gd'
$output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --disable-vsync --script $scriptPath -- "--camera=$Camera" "--subdivision=$Subdivision" "--component=$Component" "--stage=$Stage" 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Output $output
if ($code -ne 0 -or $output -notmatch 'PASS: S02 sand fixture' -or
    $output -match 'SCRIPT ERROR|SHADER ERROR|ERROR:|FAIL:') { exit 1 }
exit 0
