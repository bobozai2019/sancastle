param([ValidateSet('beach_collision_bounds_probe','sand_audit_probe','beach_mixed_failure_probe','beach_mixed_close_probe','beach_mixed_restore_probe','beach_continuous_probe','water_gpu_probe','beach_edit_process_probe','beach_pixel_feedback_probe','beach_interaction_probe','velocity_prefetch_fault_probe','velocity_probe','combined_probe','velocity_negative_probe','packed_bounds_probe','connected_runs_probe','beach_feedback_probe','beach_live_restore_probe','beach_save_boundary_probe','beach_restore_close_probe','beach_history_storage_probe','beach_same_tick_undo_probe','beach_undo_failure_probe','beach_undo_boundary_probe','beach_replay_original_probe')][string]$Probe='beach_live_restore_probe',[switch]$SandCopyTrace,[switch]$NativeBoundary,[switch]$NativeEarly,[switch]$SplitMaterialLists,[switch]$PreciseSlope,[switch]$ParameterTrace,[switch]$MaterialStageTrace,[switch]$MaterialCommitOnly,[switch]$MaterialContinuationOnly,[ValidateRange(0,38)][int]$MaterialDetailSubstep=0,[switch]$MaterialCopyFence,[ValidateSet('d3d12','vulkan')][string]$RenderingDriver='d3d12',[switch]$GpuValidation,[switch]$FastFullWet,[switch]$ProfileEditPasses,[switch]$ConnectedRuns,[switch]$PackedRuns,[switch]$PrefetchVelocity,[ValidateSet("write","read")][string]$CheckpointMode="write",[string]$CheckpointSource="",[switch]$NoParameterTrace,[switch]$CompensatedCapacity,[switch]$CachedCapacity,[switch]$ReuseCollisionShapes,[switch]$StagedSlope,[switch]$BoundedCollision,[switch]$SkipIdleComponents,[switch]$SlopeOutput,[switch]$SlopeCounter,[switch]$SlopeRecord,[switch]$StepReadbacks,[switch]$SandAuditValues,[switch]$MixedCpu,[switch]$SampleCpu,[switch]$NativeStack,[string]$CaseFilter="")
$projectPath='D:/godot/project/sandcastle'
$runDir=Join-Path $projectPath ('task/sandcastle_gpu_edit_validation/evidence/'+(Get-Date -Format yyyyMMdd_HHmmss)+'_'+$Probe)
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
$godotPath='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
$sources=@(rg --files tests/edit_validation scripts/simulation scripts/visual scripts/collision scripts/water/reference shaders/simulation tests/visual_water_alignment/prototypes scenes assets/test1_beach -g '*.gd' -g '*.glsl' -g '*.gdshader' -g '*.tscn' -g '*.tres' -g '*.json' -g '*.png' -g '*.jpg' -g '*.webp')
$sources+=@($PSCommandPath,$godotPath,(Join-Path $projectPath 'task/sandcastle_gpu_edit_validation/tools/sample_process_cpu.py'))
$index=foreach($path in $sources){$item=Get-Item -LiteralPath $path;@{path=$item.FullName;size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()}}
$index | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'manifest.json') -Encoding utf8
$compileArguments=@('--headless','--path',$projectPath,'--check-only','--script',('res://tests/edit_validation/'+$Probe+'.gd'),'--log-file',(Join-Path $runDir 'compile.log'))
$compileProcess=Start-Process -FilePath $godotPath -ArgumentList $compileArguments -WindowStyle Hidden -PassThru
@{pid=$compileProcess.Id;arguments=$compileArguments} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir 'compile_owner.json') -Encoding utf8
if(-not $compileProcess.WaitForExit(10000)){Write-Output ('compile_live_pid='+$compileProcess.Id+' output='+$runDir);return}
if($compileProcess.ExitCode -ne 0){throw ('compile failed; preserved output='+$runDir)}
$arguments=@('--path',$projectPath,'--rendering-driver',$RenderingDriver,'--resolution','1920x1080','--log-file',(Join-Path $runDir 'godot.log'),'--script',('res://tests/edit_validation/'+$Probe+'.gd'),'--',('--output='+$runDir.Replace('\','/')))
if($SandCopyTrace -or $NativeBoundary -or $NativeEarly){$arguments+='--beach-copy-sand-trace'}
if($NativeBoundary){$arguments+='--beach-copy-native-boundary'}
if($NativeEarly){$arguments+='--beach-copy-native-early'}
if($SplitMaterialLists){$arguments+='--beach-split-material-lists'}
if($PreciseSlope){$arguments+='--beach-precise-slope'}
if($ParameterTrace){$arguments+='--beach-parameter-trace';$arguments+='--beach-push-trace'}
if($MaterialStageTrace -or $MaterialCommitOnly -or $MaterialContinuationOnly){$arguments+='--beach-material-stage-trace'}
if($MaterialContinuationOnly){$arguments+='--beach-material-trace-continuation-only'}
if($MaterialCommitOnly){$arguments+='--beach-material-trace-commit-only'}
if($MaterialDetailSubstep -gt 0){$arguments+=('--beach-material-trace-detail-substep='+$MaterialDetailSubstep)}
if($MaterialCopyFence){$arguments+='--beach-material-copy-fence'}
if($Probe -eq 'beach_edit_process_probe'){$arguments+=('--checkpoint-mode='+$CheckpointMode);if($CheckpointSource){$arguments+=('--checkpoint-source='+$CheckpointSource.Replace('\','/'))}}
if($SlopeRecord -or $SlopeCounter -or $SlopeOutput){$arguments+='--beach-slope-record'}
if($SlopeCounter){$arguments+='--beach-slope-counter'}
if($SlopeOutput){$arguments+='--beach-slope-output'}
if($StagedSlope){$arguments+='--beach-staged-slope'}
if($BoundedCollision){$arguments+='--beach-bounded-collision'}
if($SkipIdleComponents){$arguments+='--skip-idle-components'}
if($StepReadbacks){$arguments+='--beach-step-readbacks'}
if($SandAuditValues){$arguments+='--sand-audit-values'}
if($MixedCpu){$arguments+='--beach-mixed-cpu'}
if($NativeStack){$arguments+='--native-wait-dump'}
if($ReuseCollisionShapes){$arguments+='--reuse-collision-shapes'}
if($CachedCapacity){$arguments+='--cached-capacity'}
if($CompensatedCapacity){$arguments+='--compensated-capacity'}
if($CaseFilter){$arguments+=('--case-filter='+$CaseFilter)}
if($NoParameterTrace){$arguments+='--beach-no-parameter-trace'}
if($PrefetchVelocity){$arguments+='--prefetch-velocity'}
if($PackedRuns){$arguments+='--packed-runs'}
if($ConnectedRuns){$arguments+='--connected-runs'}
if($ProfileEditPasses){$arguments+='--profile-edit-passes'}
if($FastFullWet){$arguments+='--fast-full-wet'}
if($GpuValidation){$arguments=@('--gpu-validation')+$arguments}
$targetProcess=Start-Process -FilePath $godotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru
@{pid=$targetProcess.Id;output=$runDir;executable=$godotPath;arguments=$arguments;scope='functional complete beach recovery; no performance claim'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir 'owner.json') -Encoding utf8
if($SampleCpu -or $NativeStack){
 $samplerArgs=@((Join-Path $projectPath 'task/sandcastle_gpu_edit_validation/tools/sample_process_cpu.py'),'--pid',$targetProcess.Id,'--output',(Join-Path $runDir 'process_cpu_samples.json'))
 if($NativeStack){$samplerArgs+=@('--dump-path',(Join-Path $runDir 'native_wait.dmp'),'--heartbeat',(Join-Path $runDir 'native_heartbeat.bin'))}
 $samplerProcess=Start-Process -FilePath 'C:/Python313/python.exe' -ArgumentList $samplerArgs -WindowStyle Hidden -RedirectStandardError (Join-Path $runDir 'sampler_error.log') -PassThru
 @{pid=$samplerProcess.Id;target_pid=$targetProcess.Id;arguments=$samplerArgs} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir 'sampler_owner.json') -Encoding utf8
}
Write-Output ($runDir+' PID '+$targetProcess.Id)
if(-not $targetProcess.WaitForExit(60000)){Write-Output ('live_pid='+$targetProcess.Id);return}
$artifacts=foreach($item in Get-ChildItem -LiteralPath $runDir -File | Where-Object Name -ne 'artifact_index.json'){@{path=$item.Name;size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()}}
$artifacts | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'artifact_index.json') -Encoding utf8
$reportPath=Join-Path $runDir ($Probe+'.json')
if(Test-Path -LiteralPath $reportPath){$report=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json; @{pass=$report.pass;checks=@($report.checks | Select-Object name,pass);row_count=@($report.rows).Count;failed_rows=@($report.rows | Where-Object { -not $_.pass } | Select-Object case,grid,policy,collision_feedback_ms);rows=@($report.rows | Where-Object { $null -ne $_.collision_feedback_ms } | Select-Object policy,collision_feedback_ms,settlement_ms,publication_ms,pass)} | ConvertTo-Json -Depth 5}else{Write-Output 'probe report missing; inspect preserved godot.log'}
if($targetProcess.ExitCode -ne 0){throw 'probe failed; all evidence preserved'}






