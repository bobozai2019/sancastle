param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe')
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$runDir = Join-Path $projectPath ('test_output/shape_brushes/g0_baseline_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $runDir | Out-Null
git -C $projectPath status --porcelain=v1 -uall | Set-Content -LiteralPath (Join-Path $runDir 'git_status.txt') -Encoding utf8
git -C $projectPath diff --binary | Set-Content -LiteralPath (Join-Path $runDir 'preexisting.diff') -Encoding utf8
$paths = @(rg --files scripts shaders scenes assets tests/shape_brushes -g '*.gd' -g '*.glsl' -g '*.gdshader' -g '*.tscn' -g '*.tres' -g '*.json' -g '*.ps1') + @('project.godot', 'AGENTS.md')
$index = foreach ($path in $paths) {
    $item = Get-Item -LiteralPath (Join-Path $projectPath $path)
    @{path=$path.Replace('\','/');size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()}
}
$arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --resolution 1280x720 --script res://tests/shape_brushes/legacy_baseline.gd -- --output="' + $runDir.Replace('\','/') + '"'
@{role='shape_brushes_g0_baseline';files=$index;engine_path=$GodotExe;engine_version=(& $GodotExe --version | Out-String).Trim();engine_sha256=(Get-FileHash -LiteralPath $GodotExe).Hash.ToLower();arguments=$arguments;headless=$false;external_processes=@(Get-Process -Name '*godot*' -ErrorAction SilentlyContinue | Select-Object Id,Path,StartTime);cost_acceptance='not_measured'} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir 'manifest.json') -Encoding utf8
$info = [System.Diagnostics.ProcessStartInfo]::new()
$info.FileName = $GodotExe
$info.Arguments = $arguments
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.WindowStyle = 'Hidden'
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$process = [System.Diagnostics.Process]::Start($info)
$stdout = $process.StandardOutput.ReadToEndAsync()
$stderr = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(240000)) { $process.Kill(); throw "Baseline timeout: $runDir" }
$stdout.Result | Set-Content -LiteralPath (Join-Path $runDir 'stdout.log') -Encoding utf8
$stderr.Result | Set-Content -LiteralPath (Join-Path $runDir 'stderr.log') -Encoding utf8
$artifacts = foreach ($item in Get-ChildItem -LiteralPath $runDir -File) { @{path=$item.Name;size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()} }
$artifacts | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'artifact_index.json') -Encoding utf8
Write-Output $runDir
if ($process.ExitCode -ne 0 -or ($stdout.Result + $stderr.Result) -match 'SCRIPT ERROR|ERROR:' -or $stdout.Result -notmatch 'MAIN_SMOKE_COMPLETE true') { throw 'Baseline failed; evidence retained' }
