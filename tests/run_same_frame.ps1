param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'gpu_same_frame_probe.gd'
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
if (-not $process.WaitForExit(30000)) {
    $process.Kill()
    Write-Output $stdoutTask.Result
    if ($stderrTask.Result) { Write-Output $stderrTask.Result }
    Write-Error 'Same-frame GPU probe timed out'
    exit 1
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
if ($process.ExitCode -ne 0 -or $stdout -notmatch 'PASS: pre-opaque main-RD compute value' -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:') {
    exit 1
}
exit 0
