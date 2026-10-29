param(
    [ValidateSet(64, 256)]
    [int]$GridSize = 64,
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'gpu_tool_patch_probe.gd'
$digests = [System.Collections.Generic.List[string]]::new()
foreach ($repeat in 1..2) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotExe
    $startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --script "' + $scriptPath + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables['SANDCASTLE_GPU_GRID'] = [string]$GridSize
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(90000)) {
        $process.Kill()
        Write-Error 'GPU tool patch probe timed out'
        exit 1
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    Write-Output $stdout
    if ($stderr) { Write-Output $stderr }
    if ($process.ExitCode -ne 0 -or $stdout -notmatch [regex]::Escape("PASS: GPU tool patch $GridSize-square") -or
            ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:') {
        exit 1
    }
    $match = [regex]::Match($stdout, 'digest=([0-9a-f]{64})')
    if (-not $match.Success) { exit 1 }
    $digests.Add($match.Groups[1].Value)
}
if ($digests[0] -ne $digests[1]) {
    Write-Error 'GPU tool patch replay digest differed'
    exit 1
}
Write-Output ('PASS: GPU tool patch deterministic replay digest=' + $digests[0])
exit 0
