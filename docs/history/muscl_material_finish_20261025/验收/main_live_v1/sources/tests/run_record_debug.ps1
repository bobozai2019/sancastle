param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'record_water_debug.gd'
$movieStagingPath = Join-Path $PSScriptRoot 'T02_water_debug_staging.avi'
$evidenceName = [string][char]0x9A8C + [string][char]0x6536
$moviePath = Join-Path (Join-Path $projectPath ('test_output\sandcastle_water_sand_coupling\' + $evidenceName)) 'T02_water_debug_20260928.avi'
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $GodotExe
$startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --fixed-fps 30 --write-movie "' + $movieStagingPath + '" --script "' + $scriptPath + '"'
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = [System.Diagnostics.Process]::Start($startInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(180000)) {
    $process.Kill()
    Write-Error 'Debug movie recording timed out'
    exit 1
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
$movie = Get-Item -LiteralPath $movieStagingPath -ErrorAction SilentlyContinue
if ($process.ExitCode -ne 0 -or $stdout -notmatch 'PASS: recorded 120 scripted debug frames' -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:' -or $null -eq $movie -or $movie.Length -lt 100000) {
    exit 1
}
Move-Item -LiteralPath $movieStagingPath -Destination $moviePath -Force -ErrorAction Stop
Write-Output ('MOVIE_BYTES=' + $movie.Length)
exit 0
