param([string]$GodotExe='D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
$projectPath=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$runDir=Join-Path $projectPath ('test_output/gpu_edit_validation/'+(Get-Date -Format yyyyMMdd_HHmmss)+'_shader_import')
New-Item -ItemType Directory -Path $runDir | Out-Null
$info=[System.Diagnostics.ProcessStartInfo]::new()
$info.FileName=$GodotExe
$info.Arguments='--headless --editor --path "'+$projectPath+'" --import'
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.WindowStyle='Hidden'
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
$p=[System.Diagnostics.Process]::Start($info)
$stdout=$p.StandardOutput.ReadToEndAsync()
$stderr=$p.StandardError.ReadToEndAsync()
$timedOut=-not $p.WaitForExit(60000)
if($timedOut){$p.Kill();$p.WaitForExit()}
$stdout.Result | Set-Content -LiteralPath (Join-Path $runDir stdout.log) -Encoding utf8
$stderr.Result | Set-Content -LiteralPath (Join-Path $runDir stderr.log) -Encoding utf8
Write-Output $runDir
Write-Output $stderr.Result
@{timed_out=$timedOut;exit_code=$p.ExitCode;arguments=$info.Arguments;process_id=$p.Id;tool_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLower()} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir result.json) -Encoding utf8
$artifacts=foreach($item in Get-ChildItem -LiteralPath $runDir -File){@{path=$item.Name;size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()}}
$artifacts | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir artifact_index.json) -Encoding utf8
if($timedOut){throw 'shader import timeout; logs/index preserved'}
if($p.ExitCode -ne 0){throw 'shader import failed'}
# Import exit is not candidate acceptance; runtime checks actual SPIRV/errors.
