param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [switch]$StillsOnly
)
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'record_full_demo.gd'
$movieStaging = Join-Path $PSScriptRoot 'T08_demo_staging.avi'
$evidenceName = [string][char]0x9A8C + [string][char]0x6536
$moviePath = Join-Path (Join-Path $projectPath ('test_output\sandcastle_water_sand_coupling\' + $evidenceName)) 'T08_full_demo_20260929.avi'
$args = '--path "' + $projectPath + '" --rendering-driver d3d12 --resolution 1280x720 --fixed-fps 30'
if (-not $StillsOnly) { $args += ' --write-movie "' + $movieStaging + '"' }
$args += ' --script "' + $scriptPath + '"'
if ($StillsOnly) { $args += ' -- --stills-only' }
$si = [System.Diagnostics.ProcessStartInfo]::new()
$si.FileName = $GodotExe
$si.Arguments = $args
$si.UseShellExecute = $false
$si.CreateNoWindow = $true
$si.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$si.RedirectStandardOutput = $true
$si.RedirectStandardError = $true
$p = [System.Diagnostics.Process]::Start($si)
$o = $p.StandardOutput.ReadToEndAsync()
$e = $p.StandardError.ReadToEndAsync()
if (-not $p.WaitForExit(2400000)) { $p.Kill(); Write-Error 'Full demo timed out'; exit 1 }
$stdout = $o.Result
$stderr = $e.Result
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
if ($p.ExitCode -ne 0 -or $stdout -notmatch 'PASS: T08 demo' -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|FAIL:') { exit 1 }
if (-not $StillsOnly) {
    $movie = Get-Item -LiteralPath $movieStaging -ErrorAction SilentlyContinue
    if ($null -eq $movie -or $movie.Length -lt 100000) { Write-Error 'Demo movie missing'; exit 1 }
    Move-Item -LiteralPath $movieStaging -Destination $moviePath -Force
    Write-Output ('MOVIE_BYTES=' + $movie.Length)
}
exit 0
