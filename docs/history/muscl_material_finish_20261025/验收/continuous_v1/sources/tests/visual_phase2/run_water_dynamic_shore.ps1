param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe',
    [ValidateSet(300,360,480)][int]$Tick = 300,
    [double]$WaterBias = 0.006)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'capture_water_fixture.gd'
$output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --script $scriptPath -- --phase2-optics --reconstruction --subdivision=2 --shoreline-debug --wave "--capture-tick=$Tick" "--water-bias=$WaterBias" 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Output $output
$suffix = if ([Math]::Abs($WaterBias - 0.006) -gt 0.0000001) { '_bias' + [Math]::Round($WaterBias * 1000) } else { '' }
if ($code -ne 0 -or $output -notmatch "PASS: W06_wave_mask_$Tick$suffix water fixture" -or
    $output -match 'SHADER ERROR|SCRIPT ERROR|ERROR:|FAIL:') {
    exit 1
}
exit 0
