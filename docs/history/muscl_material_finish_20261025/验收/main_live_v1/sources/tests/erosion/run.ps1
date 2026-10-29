param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

& (Join-Path $PSScriptRoot 'run_gpu_sediment_step.ps1') -GodotExe $GodotExe -Steps 2
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_sediment_step.ps1') -GodotExe $GodotExe -Steps 2 -Boundary
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_sediment_step.ps1') -GodotExe $GodotExe -Steps 36000
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_num09.ps1') -GodotExe $GodotExe -GridSize 64 -Ticks 300
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_num09.ps1') -GodotExe $GodotExe -GridSize 256 -Ticks 9000
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_num09_reroute.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_num08_underwater_edit.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_coupled_preview.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_process_checkpoint.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
exit 0
