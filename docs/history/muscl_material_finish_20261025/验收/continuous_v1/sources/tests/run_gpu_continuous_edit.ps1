param(
    [int]$Seconds = 60,
    [int]$CheckpointInterval = 0,
    [switch]$Coupled,
    [string]$RunTag = '',
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'gpu_continuous_edit_probe.gd'
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $GodotExe
$startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --script "' + $scriptPath + '"'
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.EnvironmentVariables['SANDCASTLE_CONTINUOUS_SECONDS'] = [string]$Seconds
$startInfo.EnvironmentVariables['SANDCASTLE_CHECKPOINT_INTERVAL'] = [string]$CheckpointInterval
$startInfo.EnvironmentVariables['SANDCASTLE_COUPLED_EDIT'] = if ($Coupled) { '1' } else { '0' }
$startInfo.EnvironmentVariables['SANDCASTLE_CONTINUOUS_RUN_TAG'] = $RunTag
$process = [System.Diagnostics.Process]::Start($startInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(($Seconds + 45) * 1000)) {
    $process.Kill()
    Write-Error 'GPU continuous edit probe timed out'
    exit 1
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
if ($process.ExitCode -ne 0 -or $stdout -notmatch 'PASS: GPU .*continuous edits=' -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|SHADER ERROR|ERROR:|FAIL:') {
    exit 1
}
exit 0
