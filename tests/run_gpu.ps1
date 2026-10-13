param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
foreach ($testCase in @(
    @{ File = 'gpu_format_probe.gd'; Expected = 'PASS: five 256-square main-RD formats support storage, sampling, copy' },
    @{ File = 'gpu_pingpong_probe.gd'; Expected = 'PASS: 256-square main-RD R32F ping-pong' },
    @{ File = 'gpu_drain_probe.gd'; Expected = 'PASS: GPU four-face positivity scale' },
    @{ File = 'gpu_shallow_edge_probe.gd'; Expected = 'PASS: GPU edge flux dam_break' },
    @{ File = 'gpu_shallow_step_probe.gd'; Expected = 'PASS: GPU shallow 64-square 1-substep dam_break' },
    @{ File = 'gpu_texture_probe.gd'; Expected = 'PASS: Texture2DRD material display' },
    @{ File = 'gpu_same_frame_probe.gd'; Expected = 'PASS: pre-opaque main-RD compute value reached opaque material' },
    @{ File = 'gpu_dirty_chunk_probe.gd'; Expected = 'PASS: packed 1/4/16 dirty chunks' },
    @{ File = 'gpu_lifecycle_probe.gd'; Expected = 'PASS: 50 main-RD compute/readback and scene rebuild cycles' }
)) {
    $scriptPath = Join-Path $PSScriptRoot $testCase.File
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotExe
    $startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --script "' + $scriptPath + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) {
        $process.Kill()
        Write-Error ('GPU test timed out: ' + $testCase.File)
        exit 1
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    Write-Output $stdout
    if ($stderr) { Write-Output $stderr }
    if ($process.ExitCode -ne 0 -or $stdout -notmatch [regex]::Escape($testCase.Expected) -or
            ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:') {
        exit 1
    }
}
& (Join-Path $PSScriptRoot 'run_gpu_steps.ps1') -GodotExe $GodotExe -Steps 1 -GridSize 64 -Case tide_rise
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_steps.ps1') -GodotExe $GodotExe -Steps 1 -GridSize 64 -Case tide_fall
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_cfl.ps1') -GodotExe $GodotExe -GridSize 64
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_tide_ticks.ps1') -GodotExe $GodotExe -GridSize 64 -Steps 30
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_tide_ticks.ps1') -GodotExe $GodotExe -GridSize 256 -Steps 1200 -DisableVsync
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_solver_display.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_tool_patch.ps1') -GodotExe $GodotExe -GridSize 64
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_preview_tool.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_tool_visibility.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_continuous_edit.ps1') -GodotExe $GodotExe -Seconds 5
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_collision_full.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_preview_undo.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_cross_tick_replay.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_checkpoint_capture.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_checkpoint_retention.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_debug_view.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_main_entry.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_preview_command_timing.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_preview_lifecycle.ps1') -GodotExe $GodotExe -Cycles 10
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_pass_timestamps.ps1') -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 64 -Preset 1 -Steps 30
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 256 -Preset 1 -Steps 30
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 256 -Case flat_lake -Steps 300 -DisableVsync
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 256 -Case uneven_lake -Steps 300 -DisableVsync
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 64 -Case dam_break -Steps 40 -DisableVsync
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 256 -Case dam_break -Steps 500 -DisableVsync
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 64 -Case curved_channel -Steps 150 -DisableVsync
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 256 -Case curved_channel -Steps 1000 -DisableVsync
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 64 -Case one_side_inlet -Steps 150 -DisableVsync
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 256 -Case one_side_inlet -Steps 300 -DisableVsync
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 64 -Case wall_opening -Steps 150 -DisableVsync
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'run_gpu_standard_scenario.ps1') -GodotExe $GodotExe -GridSize 256 -Case wall_opening -Steps 300 -DisableVsync
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'erosion/run_gpu_sediment_step.ps1') -GodotExe $GodotExe -Steps 2
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'erosion/run_gpu_sediment_step.ps1') -GodotExe $GodotExe -Steps 2 -Boundary
if ($LASTEXITCODE -ne 0) { exit 1 }
& (Join-Path $PSScriptRoot 'erosion/run_gpu_sediment_step.ps1') -GodotExe $GodotExe -Steps 36000
if ($LASTEXITCODE -ne 0) { exit 1 }
exit 0
