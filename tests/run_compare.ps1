param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'compare_solvers.gd'
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $GodotExe
$startInfo.Arguments = '--headless --path "' + $projectPath + '" --script "' + $scriptPath + '"'
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = [System.Diagnostics.Process]::Start($startInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(180000)) {
    $process.Kill()
    Write-Error "Solver comparison timed out after 180 seconds"
    exit 1
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
if ($process.ExitCode -ne 0 -or $stdout -notmatch 'PASS: 7 shared CPU solver scenarios recorded' -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:') {
    exit 1
}
exit 0
