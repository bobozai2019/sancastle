param([ValidateSet('coupled','preset0','preset1','preset2')]
    [string]$Case = 'coupled',
    [ValidateSet('frame','soak')][string]$Mode = 'frame',
    [int]$Seconds = 300, [int]$Warmup = 30,
    [string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe')
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$display = if ($Mode -eq 'frame') { @('--fullscreen','--resolution','1920x1080','--disable-vsync') } else { @('--resolution','1280x720','--disable-vsync') }
& $GodotExe --path $root --rendering-driver d3d12 @display --script (Join-Path $PSScriptRoot 'probe_sand_final_acceptance.gd') -- "--case=$Case" "--mode=$Mode" "--seconds=$Seconds" "--warmup=$Warmup"
if ($LASTEXITCODE -ne 0) { exit 1 }
exit 0
