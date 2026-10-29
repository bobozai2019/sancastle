param([string]$GodotExe='D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
$projectPath=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$runDir=Join-Path $projectPath ('test_output/gpu_edit_validation/'+(Get-Date -Format yyyyMMdd_HHmmss)+'_contract')
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
$info=[System.Diagnostics.ProcessStartInfo]::new()
$info.FileName=$GodotExe
$info.Arguments='--headless --path "'+$projectPath+'" --script res://tests/edit_validation/contract_probe.gd -- --output="'+$runDir.Replace('\','/')+'"'
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.WindowStyle='Hidden'
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
$files=@('scripts/simulation/edit_validation/edit_protocol.gd','tests/edit_validation/contract_probe.gd',
    'docs/history/sandcastle_gpu_edit_validation/契约/ADR_GPU编辑事务与水策略_v1.md',
    'docs/history/sandcastle_gpu_edit_validation/契约/编辑事务与水响应契约.md','scripts/sand/tool_command_queue.gd',
    'scripts/simulation/sand_water_domain.gd','shaders/simulation/shallow_tool_patch.glsl')
$index=foreach($relativePath in $files){
    $path=Join-Path $projectPath $relativePath
    $item=Get-Item -LiteralPath $path
    @{path=$item.FullName;size=$item.Length;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLower()}
}
@{role='contract_freeze_evidence';files=$index;arguments=$info.Arguments;
    probe='headless CPU schema and legacy preflight; no GPU candidate verdict'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir manifest.json) -Encoding utf8
$process=[System.Diagnostics.Process]::Start($info)
$stdout=$process.StandardOutput.ReadToEndAsync()
$stderr=$process.StandardError.ReadToEndAsync()
if(-not $process.WaitForExit(60000)){$process.Kill();throw 'contract probe timeout'}
$stdout.Result | Set-Content -LiteralPath (Join-Path $runDir stdout.log) -Encoding utf8
$stderr.Result | Set-Content -LiteralPath (Join-Path $runDir stderr.log) -Encoding utf8
Write-Output $runDir
Write-Output $stdout.Result
Write-Output $stderr.Result
if($process.ExitCode -ne 0 -or ($stdout.Result+$stderr.Result) -match 'SCRIPT ERROR|ERROR:'){throw 'contract probe failed'}
