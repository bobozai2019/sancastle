param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [switch]$StillsOnly
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'record_player_view.gd'
# The movie writer cannot open the non-ASCII evidence directory, so stage the
# clip on an ASCII path and move it in after the run verified.
$movieStagingPath = Join-Path $PSScriptRoot 'T04_player_view_staging.avi'
$evidenceName = [string][char]0x9A8C + [string][char]0x6536
$moviePath = Join-Path (Join-Path $projectPath ('test_output\sandcastle_water_sand_coupling\' + $evidenceName)) 'T04_player_view_20260928.avi'

$arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --resolution 1280x720 --fixed-fps 30'
if (-not $StillsOnly) {
    $arguments += ' --write-movie "' + $movieStagingPath + '"'
}
$arguments += ' --script "' + $scriptPath + '"'

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $GodotExe
$startInfo.Arguments = $arguments
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = [System.Diagnostics.Process]::Start($startInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(1800000)) {
    $process.Kill()
    Write-Error 'Player-view recording timed out'
    exit 1
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
if ($process.ExitCode -ne 0 -or $stdout -notmatch 'PASS: T04 player view' -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|FAIL:') {
    exit 1
}
if (-not $StillsOnly) {
    $movie = Get-Item -LiteralPath $movieStagingPath -ErrorAction SilentlyContinue
    if ($null -eq $movie -or $movie.Length -lt 100000) {
        Write-Error 'Player-view movie missing or too small'
        exit 1
    }
    Move-Item -LiteralPath $movieStagingPath -Destination $moviePath -Force -ErrorAction Stop
    Write-Output ('MOVIE_BYTES=' + $movie.Length)
}
exit 0
