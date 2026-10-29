param([ValidateRange(1,14)][int]$CaptureTick=5,[ValidateRange(8,24)][int]$CaptureFrames=8)
$projectPath='D:/godot/project/sandcastle'
$runDir=Join-Path $projectPath ('test_output/gpu_edit_validation/'+(Get-Date -Format yyyyMMdd_HHmmss)+'_renderdoc_original_replay')
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
$godotPath='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
$hostScript=Join-Path $PSScriptRoot 'renderdoc_replay_capture_host.py'
$sources=@(rg --files tests/edit_validation scripts/simulation scripts/visual scripts/collision scripts/water/reference shaders/simulation tests/visual_water_alignment/prototypes scenes assets/test1_beach -g '*.gd' -g '*.glsl' -g '*.gdshader' -g '*.tscn' -g '*.tres' -g '*.json' -g '*.png' -g '*.jpg' -g '*.webp')
$sources+=@($hostScript,$PSCommandPath,$godotPath,'D:/other_software/RenderDoc/qrenderdoc.exe','D:/other_software/RenderDoc/renderdoccmd.exe')
$index=foreach($path in $sources){$item=Get-Item -LiteralPath $path;@{path=$item.FullName;size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()}}
$index | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'manifest.json') -Encoding utf8
$compileArgs=@('--headless','--path',$projectPath,'--check-only','--script','res://tests/edit_validation/beach_replay_original_probe.gd','--log-file',(Join-Path $runDir 'compile.log'))
$compiler=Start-Process -FilePath $godotPath -ArgumentList $compileArgs -WindowStyle Hidden -PassThru
@{pid=$compiler.Id;arguments=$compileArgs} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir 'compile_owner.json') -Encoding utf8
if(-not $compiler.WaitForExit(10000)){Write-Output ('compile_live_pid='+$compiler.Id+' output='+$runDir);return}
if($compiler.ExitCode -ne 0){throw ('compile failed; output='+$runDir)}
$contextPath=Join-Path $PSScriptRoot 'renderdoc_replay_capture_context.json'
if(Test-Path -LiteralPath $contextPath){Remove-Item -LiteralPath $contextPath}
$hostArgs=@('--python',$hostScript)
$hostProcess=Start-Process -FilePath D:/other_software/RenderDoc/qrenderdoc.exe -ArgumentList $hostArgs -WindowStyle Hidden -PassThru
$context=@{host_pid=$hostProcess.Id;project=$projectPath;output=$runDir.Replace('\','/');godot=$godotPath;tick=$CaptureTick;frames=$CaptureFrames}
$context | ConvertTo-Json | Set-Content -LiteralPath $contextPath -Encoding utf8
@{pid=$hostProcess.Id;arguments=$hostArgs;output=$runDir;executable='D:/other_software/RenderDoc/qrenderdoc.exe'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir 'host_owner.json') -Encoding utf8
Write-Output ($runDir+' HOST PID '+$hostProcess.Id)
if(-not $hostProcess.WaitForExit(60000)){Write-Output ('capture_host_live_pid='+$hostProcess.Id);return}
$artifacts=foreach($item in Get-ChildItem -LiteralPath $runDir -File | Where-Object Name -ne 'artifact_index.json'){@{path=$item.Name;size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()}}
$artifacts | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'artifact_index.json') -Encoding utf8
Get-Content -LiteralPath (Join-Path $runDir 'capture_host.json')
if($hostProcess.ExitCode -ne 0){throw 'capture protocol failed; raw evidence preserved'}
