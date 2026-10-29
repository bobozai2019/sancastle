param([string]$GodotExe='D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
# Shared initialization/profile and visible main-RD numeric/brush negative cases.
& (Join-Path $PSScriptRoot 'run_scene_probe.ps1') -GodotExe $GodotExe
