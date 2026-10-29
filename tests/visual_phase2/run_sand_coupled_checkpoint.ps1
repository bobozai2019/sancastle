param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe')
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
& $GodotExe --path $root --rendering-driver d3d12 --resolution 1280x720 --disable-vsync --script (Join-Path $PSScriptRoot 'probe_sand_coupled_checkpoint.gd')
if ($LASTEXITCODE -ne 0) { exit 1 }
exit 0
