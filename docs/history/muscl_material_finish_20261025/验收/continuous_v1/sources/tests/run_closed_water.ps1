param(
    [int]$Seconds = 300,
    [ValidateSet('virtual_pipe', 'shallow_water', 'both')]
    [string]$Solver = 'both',
    [ValidateSet('flat', 'uneven')]
    [string]$BedMode = 'uneven',
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'closed_water_5_minutes.gd'
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $GodotExe
$startInfo.Arguments = '--headless --path "' + $projectPath + '" --script "' + $scriptPath + '"'
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.EnvironmentVariables['SANDCASTLE_CLOSED_SECONDS'] = [string]$Seconds
$startInfo.EnvironmentVariables['SANDCASTLE_CLOSED_BED'] = $BedMode
if ($Solver -eq 'both') {
    $startInfo.EnvironmentVariables['SANDCASTLE_CLOSED_SOLVER'] = ''
} else {
    $startInfo.EnvironmentVariables['SANDCASTLE_CLOSED_SOLVER'] = $Solver
}
$process = [System.Diagnostics.Process]::Start($startInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(1800000)) {
    $process.Kill()
    Write-Error "Closed-water test timed out after 1800 seconds"
    exit 1
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
if ($process.ExitCode -ne 0 -or $stdout -notmatch [regex]::Escape("PASS: closed-water $Seconds-second test") -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:') {
    exit 1
}
exit 0
