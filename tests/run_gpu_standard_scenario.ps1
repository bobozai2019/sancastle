param(
    [ValidateSet(64, 256)]
    [int]$GridSize = 64,
    [ValidateSet(0, 1, 2)]
    [int]$Preset = 0,
    [int]$Steps = 150,
    [ValidateSet('', 'flat_lake', 'uneven_lake', 'dam_break', 'curved_channel', 'one_side_inlet', 'wall_opening')]
    [string]$Case = '',
    [switch]$DisableVsync,
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'gpu_standard_scenario_probe.gd'
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $GodotExe
$startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12' +
    (' --disable-vsync' * [int]$DisableVsync.IsPresent) + ' --script "' + $scriptPath + '"'
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.EnvironmentVariables['SANDCASTLE_GPU_GRID'] = [string]$GridSize
$startInfo.EnvironmentVariables['SANDCASTLE_SCENARIO_PRESET'] = [string]$Preset
$startInfo.EnvironmentVariables['SANDCASTLE_GPU_STEPS'] = [string]$Steps
$startInfo.EnvironmentVariables['SANDCASTLE_SCENARIO_CASE'] = $Case
$process = [System.Diagnostics.Process]::Start($startInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(240000)) {
    $process.Kill()
    Write-Error 'GPU standard scenario probe timed out'
    exit 1
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
if ($process.ExitCode -ne 0 -or $stdout -notmatch 'PASS: GPU standard scenario' -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:') {
    exit 1
}
exit 0
