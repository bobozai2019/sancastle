param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'structure_save_probe.gd'
$si = [System.Diagnostics.ProcessStartInfo]::new()
$si.FileName = $GodotExe
$si.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --resolution 1280x720 --script "' + $scriptPath + '"'
$si.UseShellExecute = $false
$si.CreateNoWindow = $true
$si.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$si.RedirectStandardOutput = $true
$si.RedirectStandardError = $true
$p = [System.Diagnostics.Process]::Start($si)
$o = $p.StandardOutput.ReadToEndAsync()
$e = $p.StandardError.ReadToEndAsync()
if (-not $p.WaitForExit(900000)) { $p.Kill(); Write-Error 'Structure save probe timed out'; exit 1 }
$stdout = $o.Result
$stderr = $e.Result
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
if ($p.ExitCode -ne 0 -or $stdout -notmatch 'PASS: T08 structure save' -or
        ($stdout + $stderr) -match 'SCRIPT ERROR|FAIL:') { exit 1 }
exit 0
