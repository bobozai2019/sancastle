param(
    [ValidateSet(64, 256)]
    [int]$GridSize = 64,
    [int]$Steps = 30,
    [switch]$DisableVsync,
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'gpu_tide_tick_probe.gd'
$evidenceName = [string][char]0x9A8C + [string][char]0x6536
$evidenceDir = Join-Path $projectPath ('test_output\sandcastle_water_sand_coupling\' + $evidenceName)
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $GodotExe
$startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --script "' + $scriptPath + '"'
if ($DisableVsync) { $startInfo.Arguments += ' --disable-vsync' }
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.EnvironmentVariables['SANDCASTLE_GPU_GRID'] = [string]$GridSize
$startInfo.EnvironmentVariables['SANDCASTLE_GPU_STEPS'] = [string]$Steps
$process = [System.Diagnostics.Process]::Start($startInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$timeoutMs = if ($Steps -gt 1000) { 600000 } elseif ($GridSize -eq 256 -or $Steps -gt 30) { 180000 } else { 60000 }
if (-not $process.WaitForExit($timeoutMs)) {
    $process.Kill()
    Write-Error 'GPU tide tick probe timed out'
    exit 1
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
$tickLines = @([regex]::Matches($stdout, '(?m)^TIDE_TICK,\d+,[^\r\n]+') | ForEach-Object { $_.Value })
$summary = [regex]::Match($stdout, 'PASS: GPU tide [^\r\n]+')
if ($summary.Success) { Write-Output $summary.Value }
if ($stderr) { Write-Output $stderr }
if ($process.ExitCode -ne 0 -or $stdout -notmatch [regex]::Escape("PASS: GPU tide $GridSize-square $Steps-tick") -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:' -or $tickLines.Count -ne $Steps) {
    if (-not $summary.Success) {
        Write-Output (($stdout -split "`r?`n" | Where-Object { $_ -notmatch '^TIDE_TICK,' }) -join "`n")
    }
    exit 1
}
$csvRows = [System.Collections.Generic.List[string]]::new()
$csvRows.Add('tick,time_s,sea_level_m,substeps,gpu_water_source_m3,gpu_water_sink_m3,cpu_water_source_m3,cpu_water_sink_m3,cpu_water_m3,gpu_water_m3,gpu_gauge_depth_m,cpu_gauge_depth_m,gpu_min_depth_m,gpu_invalid_cells,gpu_negative_cells,gpu_nan_events,gpu_overload_events')
foreach ($line in $tickLines) { $csvRows.Add($line.Substring(10)) }
$csvPath = Join-Path $evidenceDir ("T03_gpu_tide_025hz_${GridSize}_${Steps}.csv")
[System.IO.File]::WriteAllLines($csvPath, $csvRows, [System.Text.UTF8Encoding]::new($false))
Write-Output ('CSV=' + $csvPath)
exit 0
