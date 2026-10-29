param(
    [int]$ReplaySteps = 8,
    [switch]$DisableVsync,
    [switch]$Coupled,
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'gpu_cross_tick_replay_probe.gd'
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $GodotExe
$startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12' +
    (' --disable-vsync' * [int]$DisableVsync.IsPresent) + ' --script "' + $scriptPath + '"'
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.EnvironmentVariables['SANDCASTLE_REPLAY_STEPS'] = [string]$ReplaySteps
$startInfo.EnvironmentVariables['SANDCASTLE_COUPLED_REPLAY'] = if ($Coupled) { '1' } else { '0' }
$process = [System.Diagnostics.Process]::Start($startInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit($(if ($Coupled) { 300000 } else { 150000 }))) {
    $process.Kill()
    Write-Error 'GPU cross-tick replay probe timed out'
    exit 1
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
if ($process.ExitCode -ne 0 -or $stdout -notmatch $(if ($Coupled) { 'PASS: GPU coupled cross-tick undo/redo' } else { 'PASS: GPU cross-tick undo/redo' }) -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|SHADER ERROR|ERROR:|FAIL:') {
    exit 1
}
exit 0
