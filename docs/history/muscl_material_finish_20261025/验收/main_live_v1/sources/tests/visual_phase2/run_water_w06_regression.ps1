param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe')

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$cases = @(
    @{ Path = 'tests\visual\run_transparency.ps1'; Args = @() },
    @{ Path = 'tests\run_gpu_steps.ps1'; Args = @('-Steps','1','-GridSize','64','-Case','tide_rise') },
    @{ Path = 'tests\run_gpu_steps.ps1'; Args = @('-Steps','1','-GridSize','64','-Case','tide_fall') },
    @{ Path = 'tests\run_gpu_cfl.ps1'; Args = @('-GridSize','64') },
    @{ Path = 'tests\run_gpu_tide_ticks.ps1'; Args = @('-GridSize','64','-Steps','30') },
    @{ Path = 'tests\run_gpu_cross_tick_replay.ps1'; Args = @() },
    @{ Path = 'tests\run_gpu_checkpoint_capture.ps1'; Args = @() },
    @{ Path = 'tests\visual_phase2\run_wave_packet.ps1'; Args = @() },
    @{ Path = 'tests\visual_phase2\run_wave_arrival.ps1'; Args = @() },
    @{ Path = 'tests\visual_phase2\run_wave_checkpoint.ps1'; Args = @('-TargetTick','1820') },
    @{ Path = 'tests\visual_phase2\run_water_foam_baseline.ps1'; Args = @() },
    @{ Path = 'tests\visual_phase2\run_water_foam.ps1'; Args = @() }
)
foreach ($case in $cases) {
    $path = Join-Path $root $case.Path
    Write-Output ('W06_REGRESSION start ' + $case.Path + ' ' + ($case.Args -join ' '))
    $caseArgs = $case.Args
    & pwsh -NoProfile -File $path -GodotExe $GodotExe @caseArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error ('W06_REGRESSION failed ' + $case.Path)
        exit 1
    }
    Write-Output ('W06_REGRESSION pass ' + $case.Path)
}
Write-Output ('PASS: W06 regression ' + $cases.Count + ' cases')
