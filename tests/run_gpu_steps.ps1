param(
    [int]$Steps = 1,
    [ValidateSet(64, 256)]
    [int]$GridSize = 64,
    [ValidateSet('all', 'dam_break', 'sloping_lake', 'wall', 'isolated_pool', 'tide_rise', 'tide_fall')]
    [string]$Case = 'all',
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'gpu_shallow_step_probe.gd'
$evidenceName = [string][char]0x9A8C + [string][char]0x6536
$evidenceDir = Join-Path $projectPath ('test_output\sandcastle_water_sand_coupling\' + $evidenceName)
$csvRows = [System.Collections.Generic.List[string]]::new()
$csvRows.Add('grid_size,substeps,case,max_depth_error_m,max_momentum_error_m2_s,max_flux_error_m3_s')
$caseNames = if ($Case -eq 'all') { @('dam_break', 'sloping_lake', 'wall') } else { @($Case) }
foreach ($caseName in $caseNames) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotExe
    $startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --script "' + $scriptPath + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables['SANDCASTLE_STEP_CASE'] = $caseName
    $startInfo.EnvironmentVariables['SANDCASTLE_GPU_STEPS'] = [string]$Steps
    $startInfo.EnvironmentVariables['SANDCASTLE_GPU_GRID'] = [string]$GridSize
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) {
        $process.Kill()
        Write-Error ('GPU shallow step probe timed out: ' + $caseName)
        exit 1
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    Write-Output $stdout
    if ($stderr) { Write-Output $stderr }
    if ($process.ExitCode -ne 0 -or $stdout -notmatch [regex]::Escape("PASS: GPU shallow $GridSize-square $Steps-substep $caseName") -or
            ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:') {
        exit 1
    }
    $match = [regex]::Match($stdout, 'CPU agreement h=([0-9.]+) q=([0-9.]+) flux=([0-9.]+)')
    if (-not $match.Success) { exit 1 }
    $csvRows.Add("$GridSize,$Steps,$caseName,$($match.Groups[1].Value),$($match.Groups[2].Value),$($match.Groups[3].Value)")
}
$caseSuffix = if ($Case -eq 'all') { '' } else { "_${Case}" }
$csvPath = Join-Path $evidenceDir ("T03_cpu_gpu_steps_${GridSize}_${Steps}${caseSuffix}.csv")
[System.IO.File]::WriteAllLines($csvPath, $csvRows, [System.Text.UTF8Encoding]::new($false))
Write-Output ('CSV=' + $csvPath)
exit 0
