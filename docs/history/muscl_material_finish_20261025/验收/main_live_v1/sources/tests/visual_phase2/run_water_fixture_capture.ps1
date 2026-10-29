param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe', [switch]$Phase2Optics,
    [ValidateSet('all','no_detail','no_specular','no_caustics')][string]$Component = 'all',
    [switch]$Reconstruction, [ValidateSet(2,4)][int]$Subdivision = 2,
    [switch]$RadialShore, [switch]$Mask, [switch]$MidpointClip)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'capture_water_fixture.gd'
if ($Reconstruction) {
    if ($MidpointClip) {
        $output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --script $scriptPath -- --phase2-optics --reconstruction "--subdivision=$Subdivision" --shoreline-debug --midpoint-clip 2>&1 | Out-String
    } elseif ($Mask) {
        $output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --script $scriptPath -- --phase2-optics --reconstruction "--subdivision=$Subdivision" --shoreline-debug 2>&1 | Out-String
    } elseif ($RadialShore) {
        $output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --script $scriptPath -- --phase2-optics --reconstruction "--subdivision=$Subdivision" --radial-shore 2>&1 | Out-String
    } else {
        $output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --script $scriptPath -- --phase2-optics --reconstruction "--subdivision=$Subdivision" 2>&1 | Out-String
    }
} elseif ($Phase2Optics) {
    if ($Mask) {
        $output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --script $scriptPath -- --phase2-optics --shoreline-debug 2>&1 | Out-String
    } else {
        $output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --script $scriptPath -- --phase2-optics "--component=$Component" 2>&1 | Out-String
    }
} else {
    $output = & $GodotExe --path $projectPath --rendering-driver d3d12 --resolution 1280x720 --script $scriptPath 2>&1 | Out-String
}
$code = $LASTEXITCODE
Write-Output $output
$expected = if ($Reconstruction -and $MidpointClip) { 'PASS: W03_midpoint_' + $Subdivision + ' water fixture' } elseif ($Reconstruction -and $Mask) { 'PASS: W03_mask_' + $Subdivision + ' water fixture' } elseif ($Reconstruction -and $RadialShore) { 'PASS: W03_radial_' + $Subdivision + ' water fixture' } elseif ($Reconstruction) { 'PASS: W03_' + $Subdivision + ' water fixture' } elseif ($Phase2Optics -and $Mask) { 'PASS: W02_mask water fixture' } elseif ($Phase2Optics -and $Component -ne 'all') { 'PASS: W02_' + $Component + ' water fixture' } elseif ($Phase2Optics) { 'PASS: W02 water fixture' } else { 'PASS: W01 water fixture' }
if ($code -ne 0 -or $output -notmatch $expected -or
    $output -match 'SHADER ERROR|SCRIPT ERROR|ERROR:|FAIL:') {
    exit 1
}
exit 0
