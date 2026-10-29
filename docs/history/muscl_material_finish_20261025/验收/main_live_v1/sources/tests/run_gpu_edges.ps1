param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'gpu_shallow_edge_probe.gd'
foreach ($caseName in @('dam_break', 'sloping_lake', 'wall')) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotExe
    $startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --script "' + $scriptPath + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables['SANDCASTLE_EDGE_CASE'] = $caseName
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) {
        $process.Kill()
        Write-Error ('GPU edge probe timed out: ' + $caseName)
        exit 1
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    Write-Output $stdout
    if ($stderr) { Write-Output $stderr }
    if ($process.ExitCode -ne 0 -or $stdout -notmatch [regex]::Escape("PASS: GPU edge flux $caseName") -or
            ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:') {
        exit 1
    }
}
exit 0
