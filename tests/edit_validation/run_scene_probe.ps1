param([string]$GodotExe='D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe', [switch]$Beach, [switch]$GpuBrush, [switch]$Matrix, [switch]$ReceiptFailure, [switch]$LocalDispatch, [switch]$MicroOnly, [switch]$WaterReference, [switch]$WaterGpu, [switch]$WaterTransaction, [switch]$WaterCurve, [switch]$WaterBridge, [switch]$Velocity, [switch]$VelocityNegative, [switch]$VelocityCurve, [switch]$StepLoss, [switch]$ObserveStepLoss, [switch]$Combined, [switch]$CombinedCurve, [switch]$Feedback, [switch]$TransactionLock, [switch]$Interaction, [switch]$InteractionQueue, [switch]$InteractionEdges, [switch]$InteractionReset, [switch]$GpuHistory, [switch]$Undo, [switch]$CheckpointCodec, [switch]$CheckpointBoundary, [switch]$CheckpointRestore, [switch]$CheckpointRestoreExit, [switch]$CrossTickUndo, [switch]$CheckpointProcess, [switch]$RedoProcess, [switch]$MixedProcess, [switch]$LegacyGuard, [switch]$ReplayExit, [switch]$AdvancedRedo, [switch]$BeachHistory, [switch]$BeachGpu, [switch]$BeachInteraction, [switch]$BeachEditProcess, [switch]$BeachSaveBoundary, [switch]$BeachCaptureFault, [switch]$BeachStepReadbacks, [switch]$BeachNoParameterTrace, [switch]$BeachLateShaderIdentity, [switch]$BeachMaterialBarriers, [switch]$BeachPushTrace, [switch]$FastRedoProcess, [string]$CheckpointMode="write", [string]$CheckpointSource="", [switch]$CollisionBatch, [switch]$CollisionExit, [switch]$Scheduler, [int]$SchedulerPolicy=0, [switch]$SchedulerAdmission, [switch]$SchedulerExit, [switch]$SchedulerFailure, [switch]$ProfileEditPasses, [switch]$FastFullWet, [string]$CaseFilter="", [int]$InteractionPolicy=1, [switch]$CombinedLarge, [int]$FeedbackPolicy=0)
$projectPath=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$runDir=Join-Path $projectPath ('test_output/gpu_edit_validation/'+(Get-Date -Format yyyyMMdd_HHmmss)+'_scenes')
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
$info=[System.Diagnostics.ProcessStartInfo]::new()
$info.FileName=$GodotExe
$probe = if($BeachCaptureFault){'beach_capture_fault_probe.gd'}elseif($BeachSaveBoundary){'beach_save_boundary_probe.gd'}elseif($BeachEditProcess){'beach_edit_process_probe.gd'}elseif($BeachInteraction){'beach_interaction_probe.gd'}elseif($BeachGpu){'beach_gpu_probe.gd'}elseif($FastRedoProcess){'fast_redo_process_probe.gd'}elseif($BeachHistory){'beach_history_process_probe.gd'}elseif($AdvancedRedo){'advanced_redo_probe.gd'}elseif($ReplayExit){'replay_exit_probe.gd'}elseif($LegacyGuard){'legacy_guard_probe.gd'}elseif($MixedProcess){'mixed_process_probe.gd'}elseif($RedoProcess){'redo_process_probe.gd'}elseif($CrossTickUndo){'cross_tick_undo_probe.gd'}elseif($CheckpointRestoreExit){'checkpoint_restore_exit_probe.gd'}elseif($CheckpointProcess -or $RedoProcess -or $MixedProcess -or $BeachHistory){'checkpoint_process_probe.gd'}elseif($CheckpointRestore){'checkpoint_restore_probe.gd'}elseif($CheckpointBoundary){'checkpoint_boundary_probe.gd'}elseif($CheckpointCodec){'checkpoint_codec_probe.gd'}elseif($Undo){'undo_probe.gd'}elseif($GpuHistory){'gpu_history_probe.gd'}elseif($InteractionReset){'interaction_reset_probe.gd'}elseif($InteractionEdges){'interaction_edges_probe.gd'}elseif($CollisionExit){'collision_exit_probe.gd'}elseif($CollisionBatch){'collision_batch_probe.gd'}elseif($InteractionQueue){'interaction_queue_probe.gd'}elseif($SchedulerFailure){'scheduler_failure_probe.gd'}elseif($SchedulerExit){'scheduler_exit_probe.gd'}elseif($SchedulerAdmission){'scheduler_admission_probe.gd'}elseif($Scheduler){'scheduler_probe.gd'}elseif($Interaction){'interaction_probe.gd'}elseif($TransactionLock){'transaction_lock_probe.gd'}elseif($Feedback){'feedback_probe.gd'}elseif($CombinedCurve){'combined_curve_probe.gd'}elseif($Combined){'combined_probe.gd'}elseif($StepLoss){'step_loss_probe.gd'}elseif($VelocityCurve){'velocity_curve_probe.gd'}elseif($VelocityNegative){'velocity_negative_probe.gd'}elseif($Velocity){'velocity_probe.gd'}elseif($WaterBridge){'water_bridge_probe.gd'}elseif($WaterCurve){'water_curve_probe.gd'}elseif($WaterTransaction){'water_transaction_probe.gd'}elseif($WaterGpu){'water_gpu_probe.gd'}elseif($WaterReference){'water_reference_probe.gd'}elseif($Beach -or $BeachHistory -or $BeachGpu -or $BeachInteraction -or $BeachEditProcess -or $BeachSaveBoundary -or $BeachCaptureFault){'beach_scene_probe.gd'}elseif($ReceiptFailure){'receipt_failure_probe.gd'}elseif($Matrix){'gpu_brush_matrix.gd'}elseif($GpuBrush){'gpu_brush_probe.gd'}else{'scene_probe.gd'}
$resolution = if($Beach -or $BeachHistory -or $BeachGpu -or $BeachInteraction -or $BeachEditProcess -or $BeachSaveBoundary -or $BeachCaptureFault){'1920x1080'}else{'960x540'}
$info.Arguments='--path "'+$projectPath+'" --rendering-driver d3d12 --resolution '+$resolution+' --script res://tests/edit_validation/'+$probe+' -- --output="'+$runDir.Replace('\','/')+'"'
if($CheckpointProcess -or $RedoProcess -or $MixedProcess -or $BeachHistory -or $FastRedoProcess -or $BeachEditProcess -or $BeachSaveBoundary -or $BeachCaptureFault){$info.Arguments+=' --checkpoint-mode='+$CheckpointMode; if($CheckpointSource){$info.Arguments+=' --checkpoint-source="'+$CheckpointSource.Replace('\','/')+'"'}}
$info.Arguments+= $(if($BeachStepReadbacks){' --beach-step-readbacks'}else{''})
if($BeachNoParameterTrace){$info.Arguments+=' --beach-no-parameter-trace'}
if($BeachLateShaderIdentity){$info.Arguments+=' --beach-late-shader-identity'}
if($BeachMaterialBarriers){$info.Arguments+=' --beach-material-barriers'}
if($BeachPushTrace){$info.Arguments+=' --beach-push-trace'}
if($LocalDispatch){$info.Arguments+=' --local-dispatch'}
if($MicroOnly){$info.Arguments+=' --micro-only'}
if($Scheduler){$info.Arguments+=" --scheduler-policy=$SchedulerPolicy"}
if($Interaction){$info.Arguments+=" --interaction-policy=$InteractionPolicy"}
if($CaseFilter){$info.Arguments+=" --case-filter=$CaseFilter"}
if($FastFullWet){$info.Arguments+=" --fast-full-wet"}
if($ProfileEditPasses){$info.Arguments+=" --profile-edit-passes"}
if($CombinedLarge){$info.Arguments+=" --combined-large"}
if($Feedback){$info.Arguments+=" --feedback-policy=$FeedbackPolicy"}
if($ObserveStepLoss){$info.Arguments+=' --observe-step-loss'}
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.WindowStyle='Hidden'
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
$sources=@(rg --files (Join-Path $projectPath 'tests/edit_validation') (Join-Path $projectPath 'scripts/simulation') (Join-Path $projectPath 'scripts/collision') (Join-Path $projectPath 'shaders/simulation') -g '*.gd' -g '*.glsl' -g '*.tscn' -g '*.tres' -g '*.gdshader' -g '*.ps1')
$sources += @(rg --files (Join-Path $projectPath 'scripts/water/reference') -g '*.gd')
if($Beach -or $BeachHistory -or $BeachGpu -or $BeachInteraction -or $BeachEditProcess -or $BeachSaveBoundary -or $BeachCaptureFault){
    $sources += @(rg --files (Join-Path $projectPath 'scripts/visual') (Join-Path $projectPath 'scripts/demo') (Join-Path $projectPath 'scenes') (Join-Path $projectPath 'assets/test1_beach') (Join-Path $projectPath 'tests/visual_water_alignment/prototypes') -g '*.gd' -g '*.glsl' -g '*.tscn' -g '*.tres' -g '*.gdshader' -g '*.json')
}
$index=foreach($path in $sources){$item=Get-Item -LiteralPath $path; @{path=$item.FullName;size=$item.Length;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLower()}}
@{files=$index;arguments=$info.Arguments;headless=$false;scope=if($Scheduler){'real GPU 64 pending reservations due order'}elseif($TransactionLock){'actual pending transaction write publication locks'}elseif($Feedback){'B C D E same camera completed tick movie frames'}elseif($CombinedCurve){'E combined 0-5s curves'}elseif($Combined){'E combined numeric'}elseif($StepLoss){'native water substep loss observer equivalence'}elseif($VelocityCurve){'independent D velocity 0-5s curves'}elseif($VelocityNegative){'native velocity negatives and CFL64 boundary'}elseif($Velocity){'native D velocity numeric and energy'}elseif($WaterBridge){'native water special state bridge'}elseif($WaterCurve){'native B C water 0-5s response curves'}elseif($WaterTransaction){'native GPU sand water transaction'}elseif($WaterGpu){'GPU water candidate isolated buffers'}elseif($WaterReference){'float64 water displacement oracle'}elseif($Beach -or $BeachHistory -or $BeachGpu -or $BeachInteraction -or $BeachEditProcess -or $BeachSaveBoundary -or $BeachCaptureFault){'inherited beach lab'}elseif($ReceiptFailure){'receipt failure rollback'}elseif($Matrix){if($MicroOnly){'GPU brush micro matrix'}else{'GPU brush matrix'}}elseif($GpuBrush){'GPU brush smoke'}else{'numeric and brush labs'};engine_path=$GodotExe;engine_sha256=(Get-FileHash -LiteralPath $GodotExe).Hash.ToLower()} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir manifest.json) -Encoding utf8
$process=[System.Diagnostics.Process]::Start($info)
$stdout=$process.StandardOutput.ReadToEndAsync()
$stderr=$process.StandardError.ReadToEndAsync()
$timedOut=-not $process.WaitForExit(180000)
if($timedOut){$process.Kill();$process.WaitForExit()}
$stdout.Result | Set-Content -LiteralPath (Join-Path $runDir stdout.log) -Encoding utf8
$stderr.Result | Set-Content -LiteralPath (Join-Path $runDir stderr.log) -Encoding utf8
Write-Output $runDir
Write-Output $stdout.Result
Write-Output $stderr.Result
$artifacts=foreach($item in Get-ChildItem -LiteralPath $runDir -File){@{path=$item.Name;size=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()}}
$artifacts | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir artifact_index.json) -Encoding utf8
if($timedOut){throw 'scene probe timeout; raw logs and hash index preserved'}
if($process.ExitCode -ne 0 -or ($stdout.Result+$stderr.Result) -match 'SCRIPT ERROR|ERROR:'){throw 'scene probe failed'}
























































