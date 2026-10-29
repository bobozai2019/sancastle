param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [switch]$Visibility
)
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$runDir = Join-Path $projectPath ('test_output/gpu_edit_validation/' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_baseline_trace')
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $GodotExe
$probe = if ($Visibility) { 'baseline_visibility_probe.gd' } else { 'baseline_trace_probe.gd' }
$startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --resolution 1920x1080 --script res://tests/edit_validation/' + $probe + ' -- --output="' + $runDir.Replace('\','/') + '"'
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.WindowStyle = 'Hidden'
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$externalProcesses = @(Get-Process -Name '*godot*' -ErrorAction SilentlyContinue | Select-Object Id,StartTime)
$paths = @(rg --files (Join-Path $projectPath 'scripts') (Join-Path $projectPath 'shaders') (Join-Path $projectPath 'scenes') (Join-Path $projectPath 'assets/test1_beach') (Join-Path $projectPath 'tests/visual_water_alignment/prototypes') $PSScriptRoot -g '*.gd' -g '*.glsl' -g '*.gdshader' -g '*.tscn' -g '*.tres' -g '*.json' -g '*.ps1')
$paths += Join-Path $projectPath 'project.godot'
$index = foreach ($path in $paths) {
    $item = Get-Item -LiteralPath $path
    @{path=$item.FullName;size=$item.Length;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLower()}
}
@{role='baseline_source_index';files=$index;engine_path=$GodotExe;
    engine_sha256=(Get-FileHash -LiteralPath $GodotExe).Hash.ToLower();
    arguments=$startInfo.Arguments;external_processes=$externalProcesses;
    external_gpu_load='unverified';cost_acceptance='diagnostic_only'} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir 'manifest.json') -Encoding utf8
$process = [System.Diagnostics.Process]::Start($startInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(180000)) { $process.Kill(); throw 'Baseline trace timeout' }
$stdoutTask.Result | Set-Content -LiteralPath (Join-Path $runDir 'stdout.log') -Encoding utf8
$stderrTask.Result | Set-Content -LiteralPath (Join-Path $runDir 'stderr.log') -Encoding utf8
Write-Output $runDir
if ($process.ExitCode -ne 0 -or ($stdoutTask.Result+$stderrTask.Result) -match 'SCRIPT ERROR|ERROR:') { throw 'Baseline trace failed; retain logs' }
if (-not $Visibility) { & (Join-Path $PSScriptRoot 'analyze_baseline.ps1') -RunDir $runDir }
$artifacts = foreach ($item in Get-ChildItem -LiteralPath $runDir -File) {
    @{path=$item.Name;size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()}
}
$artifacts | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'artifact_index.json') -Encoding utf8
