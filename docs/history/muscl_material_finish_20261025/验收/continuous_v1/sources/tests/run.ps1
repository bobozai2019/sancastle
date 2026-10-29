param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
foreach ($testCase in @(
    @{ File = 'run_tests.gd'; Expected = 'PASS: 17 simulation contract tests' },
    @{ File = 'run_scene_tests.gd'; Expected = 'PASS: 3 preset scene integration tests' },
    @{ File = 'topology_probe.gd'; Expected = 'PASS: predefined arch passes below lintel and blocks above' }
)) {
    $scriptPath = Join-Path $PSScriptRoot $testCase.File
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotExe
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = '--headless --path "' + $projectPath + '" --script "' + $scriptPath + '"'
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    Write-Output $stdout
    if ($stderr) { Write-Output $stderr }
    if ($process.ExitCode -ne 0 -or $stdout -notmatch [regex]::Escape($testCase.Expected) -or
            ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:') {
        exit 1
    }
}
exit 0
