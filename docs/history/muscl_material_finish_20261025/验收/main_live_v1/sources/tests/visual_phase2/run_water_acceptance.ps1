param([ValidateSet('frame','soak')][string]$Mode = 'frame',
    [int]$Seconds = 300, [int]$Warmup = 30,
    [string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe')

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'probe_water_acceptance.gd'
$display = if ($Mode -eq 'frame') { @('--fullscreen','--resolution','1920x1080','--disable-vsync') } else { @('--resolution','1280x720','--disable-vsync') }
$argsList = @('--path', $projectPath, '--rendering-driver', 'd3d12') + $display + @('--script', $scriptPath, '--', "--mode=$Mode", "--seconds=$Seconds", "--warmup=$Warmup")
& $GodotExe @argsList
$code = $LASTEXITCODE
if ($code -ne 0) { exit 1 }
exit 0
