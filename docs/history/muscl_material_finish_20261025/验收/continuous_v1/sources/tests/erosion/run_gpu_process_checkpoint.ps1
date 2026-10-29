param(
    [int]$ContinuationTicks = 10,
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$scriptPath = Join-Path $PSScriptRoot 'gpu_process_checkpoint_probe.gd'
$checkpointPath = Join-Path ([System.IO.Path]::GetTempPath()) ('sandcastle-checkpoint-' + [guid]::NewGuid().ToString('N') + '.bin')
$referencePath = $checkpointPath + '.reference.json'
$damagedPath = $checkpointPath + '.damaged'

function Invoke-CheckpointProbe([string]$mode) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotExe
    $startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --disable-vsync --script "' + $scriptPath + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Environment['SANDCASTLE_PROCESS_CHECKPOINT_MODE'] = $mode
    $startInfo.Environment['SANDCASTLE_PROCESS_CHECKPOINT_PATH'] = $checkpointPath
    $startInfo.Environment['SANDCASTLE_PROCESS_REFERENCE_PATH'] = $referencePath
    $startInfo.Environment['SANDCASTLE_PROCESS_CONTINUATION_TICKS'] = [string]$ContinuationTicks
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(210000)) {
        $process.Kill()
        Write-Output $stdoutTask.Result
        Write-Output $stderrTask.Result
        throw "GPU process checkpoint $mode timed out"
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    Write-Output $stdout
    if ($stderr) { Write-Output $stderr }
    $passPattern = if ($mode -eq 'write') {
        'PASS: coupled checkpoint written in process A'
    } else {
        'PASS: coupled checkpoint loaded in process B'
    }
    if ($process.ExitCode -ne 0 -or $stdout -notmatch $passPattern -or
            ($stdout + $stderr) -match 'SCRIPT ERROR|SHADER ERROR|ERROR:|FAIL:') {
        throw "GPU process checkpoint $mode failed"
    }
}

try {
    Invoke-CheckpointProbe 'write'
    Invoke-CheckpointProbe 'read'
} catch {
    Write-Error $_
    exit 1
} finally {
    foreach ($path in @($checkpointPath, $referencePath, $damagedPath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}
exit 0
