param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [int]$Preset = 1,
    [int]$Ticks = 54000,
    [int]$Sample = 300,
    [string]$Out = 'T08_stability_scn02_20260929.csv',
    [int]$Structures = 0,
    [switch]$Fullscreen1080p,
    ## Windows throttles a hidden window, which distorts a long run's frame rate.
    ## Leave it visible when the run itself is the measurement.
    [switch]$Visible
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'long_stability_probe.gd'
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $GodotExe
$display = if ($Fullscreen1080p) { '--fullscreen --resolution 1920x1080 --disable-vsync' } else { '--resolution 1280x720' }
$startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 ' + $display + ' --script "' + $scriptPath +
    '" -- --preset ' + $Preset + ' --ticks ' + $Ticks + ' --sample ' + $Sample + ' --out ' + $Out +
    ' --structures ' + $Structures + ' --highres ' + [int]$Fullscreen1080p.IsPresent
$startInfo.UseShellExecute = $false
if ($Visible) {
    $startInfo.CreateNoWindow = $false
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
} else {
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
}
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = [System.Diagnostics.Process]::Start($startInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(7200000)) {
    $process.Kill()
    Write-Error 'Long stability run timed out'
    exit 1
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
if ($process.ExitCode -ne 0 -or $stdout -notmatch 'PASS: T08 stability' -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|FAIL:') {
    exit 1
}
exit 0
