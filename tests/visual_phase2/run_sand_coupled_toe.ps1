param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe',
    [switch]$NoWave)
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$extra = if ($NoWave) { @('--','--no-wave') } else { @() }
& $GodotExe --path $root --rendering-driver d3d12 --resolution 1280x720 --disable-vsync --script (Join-Path $PSScriptRoot 'probe_sand_coupled_toe.gd') @extra
if ($LASTEXITCODE -ne 0) { exit 1 }
exit 0
