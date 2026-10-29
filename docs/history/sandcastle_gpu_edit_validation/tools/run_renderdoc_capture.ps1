param([ValidateSet('write','read')][string]$Mode='write',[string]$Source='')
$projectPath='D:/godot/project/sandcastle'
$runDir=Join-Path $projectPath ('task/sandcastle_gpu_edit_validation/evidence/'+(Get-Date -Format yyyyMMdd_HHmmss)+'_renderdoc')
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
$contextPath=Join-Path $PSScriptRoot 'renderdoc_capture_context.json'
if(Test-Path -LiteralPath $contextPath){Remove-Item -LiteralPath $contextPath}
$sources=@(rg --files tests/edit_validation scripts/simulation scripts/visual scripts/collision shaders/simulation tests/visual_water_alignment/prototypes scenes assets/test1_beach -g '*.gd' -g '*.glsl' -g '*.gdshader' -g '*.tscn' -g '*.tres' -g '*.json')
$sources+=@((Join-Path $PSScriptRoot 'renderdoc_capture_host.py'),$PSCommandPath,'D:/other_software/RenderDoc/qrenderdoc.exe','D:/other_software/RenderDoc/renderdoccmd.exe','D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
$index=foreach($path in $sources){$item=Get-Item -LiteralPath $path; @{path=$item.FullName;size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()}}
@{scope='own Godot D3D12 capture';sources=$index} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'manifest.json') -Encoding utf8
$hostProcess=Start-Process -FilePath D:/other_software/RenderDoc/qrenderdoc.exe -ArgumentList @('--python',(Join-Path $PSScriptRoot 'renderdoc_capture_host.py')) -WindowStyle Hidden -PassThru
@{host_pid=$hostProcess.Id;project=$projectPath;output=$runDir.Replace('\','/');godot='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe';mode=$Mode;source=$Source} | ConvertTo-Json | Set-Content -LiteralPath $contextPath -Encoding utf8
$exited=$hostProcess.WaitForExit(170000)
Write-Output $runDir
if(-not $exited){Write-Output ('capture_host_live_pid='+$hostProcess.Id);throw 'capture host observation timeout; inspect this owned PID before further action'}
$artifacts=foreach($item in Get-ChildItem -LiteralPath $runDir -File){try{$hash=(Get-FileHash -LiteralPath $item.FullName -ErrorAction Stop).Hash.ToLower();@{path=$item.Name;size=$item.Length;sha256=$hash;status='read'}}catch{@{path=$item.Name;size=$item.Length;sha256=$null;status='locked_or_incomplete';error=$_.Exception.Message}}}
$artifacts | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'artifact_index.json') -Encoding utf8
Get-Content -LiteralPath (Join-Path $runDir 'capture_host.json')
if($hostProcess.ExitCode -ne 0){throw 'capture host failed; raw evidence preserved'}
