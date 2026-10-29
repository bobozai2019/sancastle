param([ValidateSet('cpu','gpu')][string]$Backend='gpu',[ValidateRange(0,3)][int]$Policy=0,[ValidateRange(0,300)][int]$Warmup=2,[ValidateRange(1,1800)][int]$Seconds=22,[switch]$BoundedCollision,[switch]$WaitPhases,[switch]$NativeStack,[switch]$ProfileEditPasses,[switch]$RenderTiming,[ValidateSet(0,60)][int]$MaxFps=0,[switch]$SkipIdleComponents)
$projectPath='D:/godot/project/sandcastle'
$godotPath='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
$runDir=Join-Path $projectPath ('task/sandcastle_gpu_edit_validation/evidence/'+(Get-Date -Format yyyyMMdd_HHmmss)+'_beach_cost_'+$Backend+'_B'+$Policy)
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
$sourcePaths=@(rg --files tests/edit_validation scripts/simulation scripts/visual scripts/collision scripts/water/reference shaders/simulation tests/visual_water_alignment/prototypes scenes assets/test1_beach -g '*.gd' -g '*.glsl' -g '*.gdshader' -g '*.tscn' -g '*.tres' -g '*.json' -g '*.png' -g '*.jpg' -g '*.webp')
$sourcePaths+=@($PSCommandPath,$godotPath,(Join-Path $projectPath 'task/sandcastle_gpu_edit_validation/tools/sample_process_cpu.py'),(Join-Path $projectPath 'task/sandcastle_gpu_edit_validation/tools/inspect_native_minidump.py'))
$manifest=foreach($path in $sourcePaths){$item=Get-Item -LiteralPath $path;@{path=$item.FullName;size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()}}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'manifest.json') -Encoding utf8
@{cpu=@(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors);gpu=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterRAM);os=@(Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version);backend='d3d12';resolution='1920x1080';vsync='off'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'hardware.json') -Encoding utf8
$arguments=@('--path',$projectPath,'--rendering-driver','d3d12','--resolution','1920x1080','--log-file',(Join-Path $runDir 'godot.log'),'--script','res://tests/edit_validation/beach_cost_probe.gd','--',('--output='+$runDir.Replace('\','/')),('--backend='+$Backend),('--policy='+$Policy),('--warmup='+$Warmup),('--seconds='+$Seconds),'--beach-staged-slope','--compensated-capacity','--packed-runs','--cached-capacity','--prefetch-velocity','--beach-no-parameter-trace')
if($BoundedCollision){$arguments+='--beach-bounded-collision'}
if($WaitPhases -or $NativeStack){$arguments+='--cost-wait-phases'}
if($NativeStack){$arguments+='--native-wait-dump'}
if($ProfileEditPasses){$arguments+='--profile-edit-passes'}
if($RenderTiming){$arguments+='--cost-render-timing'}
if($SkipIdleComponents){$arguments+='--skip-idle-components'}
$arguments=@('--max-fps',([string]$MaxFps))+$arguments
$targetProcess=Start-Process -FilePath $godotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru
@{pid=$targetProcess.Id;output=$runDir;executable=$godotPath;arguments=$arguments;scope='visible full beach cost, fixed nominal wall-clock input; inspect runtime trace for actual configuration'} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'owner.json') -Encoding utf8
Write-Output ('output='+$runDir+' pid='+$targetProcess.Id)
if($NativeStack){
 $samplerArguments=@((Join-Path $projectPath 'task/sandcastle_gpu_edit_validation/tools/sample_process_cpu.py'),'--pid',$targetProcess.Id,'--output',(Join-Path $runDir 'process_cpu_samples.json'),'--dump-path',(Join-Path $runDir 'native_wait.dmp'),'--heartbeat',(Join-Path $runDir 'native_heartbeat.bin'),'--active-window-us',([string](($Seconds+1)*1000000)))
 $samplerProcess=Start-Process -FilePath 'C:/Python313/python.exe' -ArgumentList $samplerArguments -WindowStyle Hidden -RedirectStandardError (Join-Path $runDir 'sampler_error.log') -PassThru
 @{pid=$samplerProcess.Id;target_pid=$targetProcess.Id;arguments=$samplerArguments} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'sampler_owner.json') -Encoding utf8
}
if(-not $targetProcess.WaitForExit(60000)){Write-Output ('live_pid='+$targetProcess.Id);return}
Write-Output ('exit_code='+$targetProcess.ExitCode)
