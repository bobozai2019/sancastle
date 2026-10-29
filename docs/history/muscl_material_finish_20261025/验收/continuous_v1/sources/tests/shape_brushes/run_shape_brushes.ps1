param(
    [string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe',
    [ValidateSet('d3d12','vulkan')][string]$RenderingDriver = 'd3d12',
    [switch]$GpuValidation,
    [string]$VulkanImplicitLayerPath = '',
    [ValidateSet('contract','input','framework','legacy_pair','inventory','wall','retention','local_material','material_diagnosis','material_repeat_900','material_tick_trace','original_repeat_900','precision_repeat','material_precision_smoke','material_precision_repeat','immutable_smoke','immutable_repeat','snapshot_repeat','stage_log_smoke','stage_log_repeat','barrier_smoke','barrier_repeat','ordered_snapshot_repeat','material_edit','material_damage','material_state','material_hot_zero','material_init_failure','material_operator','native_material','checkpoint_v4','water','water_fault','water_guard','castle','castle_resource','castle_click','shovel','shovel_path','shovel_side','shovel_edge','shape_evolution','ui','ui_matrix','formal_layout','collision_matrix','continuation','soak_cost','stage_cost','checkpoint_memory','lifecycle','integration','legacy_affected','direct_entries','legacy_drag','fixed_stage','engine_identity','material_list_smoke','scratch_restore','runtime_profile','legacy_pointer','continuation_inputs','engine_checkpoint','final')][string]$Group = 'input',
    [string]$OutputRoot = 'D:\godot\project\sandcastle\test_output\shape_brushes'
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if ($VulkanImplicitLayerPath) {
    if ($RenderingDriver -ne 'vulkan' -or -not [System.IO.Path]::IsPathRooted($VulkanImplicitLayerPath) -or -not (Test-Path -LiteralPath $VulkanImplicitLayerPath -PathType Container)) { throw 'VulkanImplicitLayerPath requires Vulkan and an existing absolute directory' }
    $VulkanImplicitLayerPath = (Resolve-Path -LiteralPath $VulkanImplicitLayerPath).Path
}
if (-not [System.IO.Path]::IsPathRooted($OutputRoot) -or $OutputRoot -match '[^\x20-\x7e]') { throw 'OutputRoot must be an absolute English path' }
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputRoot)
$runDir = Join-Path $resolvedOutput ((Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + $Group + '_' + [guid]::NewGuid().ToString('N').Substring(0,8))
$jobs = switch ($Group) {
    'engine_checkpoint' { @{name='engine_checkpoint';script='res://tests/shape_brushes/engine_checkpoint_probe.gd';report='main_smoke.json'} }
    'continuation_inputs' {
        @{name='continuation_inputs';script='res://tests/shape_brushes/continuation_inputs_probe.gd';report='main_smoke.json';timeout_ms=900000}
        @{name='input_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'continuation_inputs_reference.py');report='result.json';python=$true}
    }
    'legacy_pointer' { @{name='approx_functional';script='res://tests/experiments/approx_gpu_edit/functional_probe.gd';report='result.json'} }
    'runtime_profile' {
        @{name='runtime_profile';script='res://tests/shape_brushes/runtime_profile_probe.gd';report='main_smoke.json'}
        @{name='profile_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'runtime_profile_reference.py');report='result.json';python=$true}
    }
    'scratch_restore' { @{name='scratch_restore';script='res://tests/shape_brushes/scratch_restore_probe.gd';report='main_smoke.json';timeout_ms=900000} }
    'material_list_smoke' {
        @{name='ordinary_control';script='res://tests/shape_brushes/retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=5'}
        @{name='zero_support';script='res://tests/shape_brushes/local_material_probe.gd';report='main_smoke.json';extra=' --mode=zero_support --ticks=5'}
        @{name='local';script='res://tests/shape_brushes/local_material_probe.gd';report='main_smoke.json';extra=' --mode=local --ticks=5'}
    }
    'engine_identity' { @{name='engine_identity';script='res://tests/shape_brushes/engine_identity_probe.gd';report='main_smoke.json';headless=$true} }
    'fixed_stage' { @{name='fixed_stage';script='res://tests/shape_brushes/fixed_stage_probe.gd';report='main_smoke.json'} }
    'legacy_drag' { @{name='legacy_drag';script='res://tests/shape_brushes/legacy_drag_probe.gd';report='main_smoke.json';timeout_ms=900000} }
    'direct_entries' { @{name='direct_entries';script='res://tests/shape_brushes/final_probe.gd';report='main_smoke.json';timeout_ms=900000} }
    'legacy_affected' {
        @{name='approx_functional';script='res://tests/experiments/approx_gpu_edit/functional_probe.gd';report='result.json'}
        @{name='approx_lifecycle';script='res://tests/experiments/approx_gpu_edit/lifecycle_probe.gd';report='result.json'}
        @{name='checkpoint_v4';script='res://tests/shape_brushes/checkpoint_v4_probe.gd';report='main_smoke.json'}
    }
    'final' {
        @{name='cpu_contract';script='res://tests/run_tests.gd';report='result.json';log_pass='PASS: 17 simulation contract tests';headless=$true}
        @{name='topology';script='res://tests/topology_probe.gd';report='result.json';log_pass='PASS: predefined arch passes below lintel and blocks above; heightfield wall blocks below';headless=$true}
        @{name='input';script='res://tests/shape_brushes/input_contract_probe.gd';report='input_result.json';headless=$true}
        @{name='inventory';script='res://tests/shape_brushes/inventory_gpu_probe.gd';report='main_smoke.json'}
        @{name='legacy_pair';script='res://tests/shape_brushes/legacy_pair_probe.gd';report='main_smoke.json'}
        @{name='direct_entries';script='res://tests/shape_brushes/final_probe.gd';report='main_smoke.json';timeout_ms=900000}
    }
    'checkpoint_memory' { @{name='checkpoint_memory';script='res://tests/shape_brushes/checkpoint_memory_probe.gd';report='main_smoke.json';timeout_ms=900000} }
    'stage_cost' { @{name='stage_cost';script='res://tests/shape_brushes/stage_cost_probe.gd';report='main_smoke.json';timeout_ms=900000} }
    'lifecycle' { @{name='lifecycle';script='res://tests/shape_brushes/lifecycle_probe.gd';report='main_smoke.json';timeout_ms=900000} }
    'soak_cost' { @{name='soak_cost';script='res://tests/shape_brushes/soak_cost_probe.gd';report='main_smoke.json';timeout_ms=900000} }
    'continuation' { @{name='continuation';script='res://tests/shape_brushes/continuation_probe.gd';report='main_smoke.json';timeout_ms=900000} }
    'collision_matrix' { @{name='collision_matrix';script='res://tests/shape_brushes/collision_matrix_probe.gd';report='main_smoke.json'} }
    'water_guard' {
        @{name='water_guard';script='res://tests/shape_brushes/water_guard_probe.gd';report='main_smoke.json'}
        @{name='guard_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'water_guard_reference.py');report='result.json';python=$true}
    }
    'shape_evolution' {
        @{name='castle_intact';script='res://tests/shape_brushes/shape_evolution_probe.gd';report='main_smoke.json';extra=' --mode=castle_intact';timeout_ms=900000}
        @{name='castle_damaged';script='res://tests/shape_brushes/shape_evolution_probe.gd';report='main_smoke.json';extra=' --mode=castle_damaged';timeout_ms=900000}
        @{name='wet_wave';script='res://tests/shape_brushes/shape_evolution_probe.gd';report='main_smoke.json';extra=' --mode=wet_wave';timeout_ms=900000}
        @{name='evolution_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'shape_evolution_reference.py');report='result.json';python=$true}
    }
    'shovel_edge' {
        @{name='shovel_gpu';script='res://tests/shape_brushes/shovel_edge_probe.gd';report='main_smoke.json'}
        @{name='shovel_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'shovel_reference.py');report='result.json';python=$true}
    }
    'shovel_side' { @{name='shovel_side';script='res://tests/shape_brushes/shovel_side_probe.gd';report='main_smoke.json'} }
    'shovel_path' {
        @{name='shovel_path';script='res://tests/shape_brushes/shovel_path_probe.gd';report='main_smoke.json';timeout_ms=900000}
        @{name='path_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'shovel_path_reference.py');report='result.json';python=$true}
    }
    'castle_click' { @{name='castle_click';script='res://tests/shape_brushes/castle_click_probe.gd';report='main_smoke.json'} }
    'formal_layout' { @{name='formal_layout';script='res://tests/shape_brushes/formal_layout_probe.gd';report='main_smoke.json'} }
    'castle_resource' { @{name='castle_resource';script='res://tests/shape_brushes/castle_resource_probe.gd';report='main_smoke.json'} }
    'ui_matrix' { @{name='ui_matrix';script='res://tests/shape_brushes/ui_matrix_probe.gd';report='main_smoke.json'} }
    'water_fault' { @{name='water_fault';script='res://tests/shape_brushes/water_fault_probe.gd';report='main_smoke.json';expected_errors=@('shape GPU dispatch failed','shape GPU receipt mismatch')} }
    'integration' { @{name='formal_scene';script='res://tests/shape_brushes/formal_scene_probe.gd';report='main_smoke.json';timeout_ms=900000} }
    'water' {
        @{name='water_gpu';script='res://tests/shape_brushes/water_probe.gd';report='main_smoke.json'}
        @{name='water_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'water_reference.py');report='result.json';python=$true}
    }
    'checkpoint_v4' { @{name='checkpoint_v4';script='res://tests/shape_brushes/checkpoint_v4_probe.gd';report='main_smoke.json'} }
    'ui' { @{name='ui_gpu';script='res://tests/shape_brushes/ui_probe.gd';report='main_smoke.json'} }
    'shovel' {
        @{name='shovel_gpu';script='res://tests/shape_brushes/shovel_probe.gd';report='main_smoke.json'}
        @{name='shovel_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'shovel_reference.py');report='result.json';python=$true}
    }
    'legacy_pair' { @{name='legacy_pair';script='res://tests/shape_brushes/legacy_pair_probe.gd';report='main_smoke.json'} }
    'castle' {
        @{name='castle_gpu';script='res://tests/shape_brushes/castle_probe.gd';report='main_smoke.json'}
        @{name='castle_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'castle_reference.py');report='result.json';python=$true}
    }
    'contract' {
        @{name='spec';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'check_contract.py');report='contract_result.json';python=$true}
        @{name='legacy_inventory';script='res://tests/shape_brushes/legacy_inventory_contract.gd';report='legacy_inventory.json'}
        @{name='legacy_protocol';script='res://tests/edit_validation/contract_probe.gd';report='contract_probe.json'}
    }
    'input' { @{name='input';script='res://tests/shape_brushes/input_contract_probe.gd';report='input_result.json'} }
    'inventory' { @{name='inventory';script='res://tests/shape_brushes/inventory_gpu_probe.gd';report='main_smoke.json'} }
    'wall' {
        @{name='wall_gpu';script='res://tests/shape_brushes/wall_probe.gd';report='main_smoke.json'}
        @{name='reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'wall_reference.py');report='result.json';python=$true}
    }
    'retention' {
        @{name='baseline';script='res://tests/shape_brushes/retention_probe.gd';report='main_smoke.json';extra=' --mode=baseline --ticks=900';timeout_ms=900000}
        @{name='compact';script='res://tests/shape_brushes/retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='cohesion';script='res://tests/shape_brushes/retention_probe.gd';report='main_smoke.json';extra=' --mode=cohesion --ticks=900';timeout_ms=900000}
        @{name='control_analysis';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'retention_reference.py');report='result.json';python=$true}
    }
    'local_material' {
        @{name='ordinary_control';script='res://tests/shape_brushes/retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='zero_support';script='res://tests/shape_brushes/local_material_probe.gd';report='main_smoke.json';extra=' --mode=zero_support --ticks=900';timeout_ms=900000}
        @{name='local';script='res://tests/shape_brushes/local_material_probe.gd';report='main_smoke.json';extra=' --mode=local --ticks=900';timeout_ms=900000}
        @{name='local_analysis';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'local_material_reference.py');report='result.json';python=$true}
    }
    'material_diagnosis' {
        @{name='original_a';script='res://tests/shape_brushes/retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=400';timeout_ms=900000}
        @{name='original_b';script='res://tests/shape_brushes/retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=400';timeout_ms=900000}
        @{name='zero_support';script='res://tests/shape_brushes/local_material_probe.gd';report='main_smoke.json';extra=' --mode=zero_support --ticks=400';timeout_ms=900000}
    }
    'material_repeat_900' {
        @{name='original_a';script='res://tests/shape_brushes/retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='original_b';script='res://tests/shape_brushes/retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='repeat_analysis';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'material_repeat_reference.py');report='result.json';python=$true}
    }
    'material_tick_trace' {
        @{name='original_a';script='res://tests/shape_brushes/material_tick_trace_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='original_b';script='res://tests/shape_brushes/material_tick_trace_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='repeat_analysis';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'material_tick_trace_reference.py');report='result.json';python=$true}
    }
    'original_repeat_900' {
        @{name='original_a';script='res://tests/shape_brushes/original_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='original_b';script='res://tests/shape_brushes/original_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='repeat_analysis';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'material_repeat_reference.py');report='result.json';python=$true}
    }
    'material_edit' {
        @{name='material_edit';script='res://tests/shape_brushes/material_edit_probe.gd';report='main_smoke.json';expected_errors=@('shape GPU dispatch failed','shape GPU receipt mismatch','beach GPU dispatch failed')}
        @{name='material_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'material_edit_reference.py');report='result.json';python=$true}
    }
    'material_damage' {
        @{name='intact';script='res://tests/shape_brushes/material_damage_probe.gd';report='main_smoke.json';extra=' --mode=intact';timeout_ms=900000}
        @{name='trench';script='res://tests/shape_brushes/material_damage_probe.gd';report='main_smoke.json';extra=' --mode=trench';timeout_ms=900000}
        @{name='damage_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'material_damage_reference.py');report='result.json';python=$true}
    }
    'material_state' { @{name='material_state';script='res://tests/shape_brushes/material_state_probe.gd';report='main_smoke.json'} }
    'material_hot_zero' { @{name='material_hot_zero';script='res://tests/shape_brushes/material_hot_zero_probe.gd';report='main_smoke.json'} }
    'material_init_failure' { @{name='material_init_failure';script='res://tests/shape_brushes/material_init_failure_probe.gd';report='main_smoke.json';expected_error='GPU shallow solver initialization failed'} }
    'native_material' { @{name='native_material';script='res://tests/shape_brushes/native_material_probe.gd';report='main_smoke.json'} }
    'material_operator' {
        @{name='material_operator';script='res://tests/shape_brushes/material_operator_probe.gd';report='main_smoke.json'}
        @{name='operator_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'material_operator_reference.py');report='result.json';python=$true}
    }
    'precision_repeat' {
        @{name='native_a';script='res://tests/shape_brushes/original_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='native_b';script='res://tests/shape_brushes/original_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='precise_a';script='res://tests/shape_brushes/precise_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='precise_b';script='res://tests/shape_brushes/precise_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='precision_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'precision_repeat_reference.py');report='result.json';python=$true}
    }
    'snapshot_repeat' {
        @{name='original_a';script='res://tests/shape_brushes/snapshot_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='original_b';script='res://tests/shape_brushes/snapshot_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='repeat_analysis';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'material_repeat_reference.py');report='result.json';python=$true}
    }
    'stage_log_smoke' {
        @{name='stage_log_smoke';script='res://tests/shape_brushes/stage_log_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=5'}
        @{name='hash_calibration';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'stage_hash_smoke_reference.py');report='result.json';python=$true}
    }
    'stage_log_repeat' {
        @{name='original_a';script='res://tests/shape_brushes/stage_log_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='original_b';script='res://tests/shape_brushes/stage_log_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='stage_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'stage_log_reference.py');report='result.json';python=$true}
    }
    'barrier_smoke' { @{name='barrier_smoke';script='res://tests/shape_brushes/barrier_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=5'} }
    'barrier_repeat' {
        @{name='original_a';script='res://tests/shape_brushes/barrier_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='original_b';script='res://tests/shape_brushes/barrier_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='repeat_analysis';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'material_repeat_reference.py');report='result.json';python=$true}
    }
    'ordered_snapshot_repeat' {
        @{name='original_a';script='res://tests/shape_brushes/ordered_snapshot_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='original_b';script='res://tests/shape_brushes/ordered_snapshot_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='repeat_analysis';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'material_repeat_reference.py');report='result.json';python=$true}
    }
    'material_precision_smoke' { @{name='material_precision_smoke';script='res://tests/shape_brushes/material_precision_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=5 --variant=precise'} }
    'immutable_smoke' { @{name='immutable_smoke';script='res://tests/shape_brushes/immutable_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=5'} }
    'immutable_repeat' {
        @{name='original_a';script='res://tests/shape_brushes/immutable_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='original_b';script='res://tests/shape_brushes/immutable_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900';timeout_ms=900000}
        @{name='repeat_analysis';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'material_repeat_reference.py');report='result.json';python=$true}
    }
    'material_precision_repeat' {
        @{name='native_a';script='res://tests/shape_brushes/material_precision_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900 --variant=original';timeout_ms=900000}
        @{name='native_b';script='res://tests/shape_brushes/material_precision_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900 --variant=original';timeout_ms=900000}
        @{name='precise_a';script='res://tests/shape_brushes/material_precision_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900 --variant=precise';timeout_ms=900000}
        @{name='precise_b';script='res://tests/shape_brushes/material_precision_retention_probe.gd';report='main_smoke.json';extra=' --mode=compact --ticks=900 --variant=precise';timeout_ms=900000}
        @{name='precision_reference';exe=(Get-Command python).Source;script=(Join-Path $PSScriptRoot 'precision_repeat_reference.py');report='result.json';python=$true}
    }
    'framework' {
        @{name='lab_entry';script='res://tests/shape_brushes/lab_entry_probe.gd';report='main_smoke.json'}
        @{name='gpu_framework';script='res://tests/shape_brushes/gpu_framework_probe.gd';report='main_smoke.json'}
        @{name='transport_failure';script='res://tests/shape_brushes/gpu_fault_probe.gd';report='main_smoke.json';extra=' --fault=transport';expected_error='shape GPU dispatch failed'}
        @{name='identity_failure';script='res://tests/shape_brushes/gpu_fault_probe.gd';report='main_smoke.json';extra=' --fault=identity';expected_error='shape GPU receipt mismatch'}
        @{name='legacy_pair';script='res://tests/shape_brushes/legacy_pair_probe.gd';report='main_smoke.json'}
        @{name='close';script='res://tests/shape_brushes/close_probe.gd';report='main_smoke.json'}
    }
    default {
        $futureScript = 'res://tests/shape_brushes/' + $Group + '_probe.gd'
        if (-not (Test-Path -LiteralPath (Join-Path $projectPath $futureScript.Substring(6)))) { throw "Group $Group has not been implemented; no test was run" }
        @{name=$Group;script=$futureScript;report='result.json'}
    }
}
New-Item -ItemType Directory -Path $runDir | Out-Null
$groupHeadless = $Group -in @('contract','input','material_state')
$sources = @(rg --files (Join-Path $projectPath 'scripts') (Join-Path $projectPath 'shaders') (Join-Path $projectPath 'scenes') (Join-Path $projectPath 'assets/brushes') (Join-Path $projectPath 'tests') -g '*.gd' -g '*.glsl' -g '*.glslinc' -g '*.gdshader' -g '*.tres' -g '*.json' -g '*.ps1' -g '*.py' -g '*.tscn' -g '*.rgba32f')
$sourceIndex = foreach ($path in $sources) { $item=Get-Item -LiteralPath $path; @{path=$item.FullName;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLower()} }
$commands = @()
$results = @()
foreach ($job in $jobs) {
    $headless = $groupHeadless -or $job.headless -eq $true
    $jobDir = Join-Path $runDir $job.name
    New-Item -ItemType Directory -Path $jobDir | Out-Null
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = if ($job.python) { $job.exe } else { $GodotExe }
    $info.Arguments = if ($job.python) { '"' + $job.script + '" --output "' + $jobDir + '"' } else { '--path "' + $projectPath + '" ' + $(if ($headless) {'--headless '} else {'--rendering-driver ' + $RenderingDriver + ' --resolution 1280x720 '}) + $(if ($GpuValidation) {'--gpu-validation '}else{''}) + '--script ' + $job.script + ' -- --output="' + $jobDir.Replace('\','/') + '"' }
    $info.WorkingDirectory = $projectPath
    if ($job.extra) { $info.Arguments += $job.extra }
    $info.UseShellExecute = $false
    if ($VulkanImplicitLayerPath -and -not $job.python) { $info.EnvironmentVariables['VK_IMPLICIT_LAYER_PATH'] = $VulkanImplicitLayerPath }
    $info.CreateNoWindow = $true
    $info.WindowStyle = 'Hidden'
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $commands += @{exe=$info.FileName;arguments=$info.Arguments;headless=$headless}
    $process = [System.Diagnostics.Process]::Start($info)
    $stdoutWriter = [System.IO.StreamWriter]::new((Join-Path $jobDir 'stdout.log'),$false,[System.Text.UTF8Encoding]::new($false))
    $stderrWriter = [System.IO.StreamWriter]::new((Join-Path $jobDir 'stderr.log'),$false,[System.Text.UTF8Encoding]::new($false))
    $stdoutWriter.AutoFlush = $true; $stderrWriter.AutoFlush = $true
    $stdoutText = [System.Text.StringBuilder]::new(); $stderrText = [System.Text.StringBuilder]::new()
    $stdoutRead = $process.StandardOutput.ReadLineAsync(); $stderrRead = $process.StandardError.ReadLineAsync()
    $elapsed = [System.Diagnostics.Stopwatch]::StartNew(); $timedOut = $false
    $jobTimeoutMs = if ($job.timeout_ms) { [int]$job.timeout_ms } else { 240000 }
    while (-not $process.HasExited -or $null -ne $stdoutRead -or $null -ne $stderrRead) {
        while ($null -ne $stdoutRead -and $stdoutRead.IsCompleted) {
            $line = $stdoutRead.Result
            if ($null -eq $line) { $stdoutRead=$null } else { $stdoutWriter.WriteLine($line); $null=$stdoutText.AppendLine($line); $stdoutRead=$process.StandardOutput.ReadLineAsync() }
        }
        while ($null -ne $stderrRead -and $stderrRead.IsCompleted) {
            $line = $stderrRead.Result
            if ($null -eq $line) { $stderrRead=$null } else { $stderrWriter.WriteLine($line); $null=$stderrText.AppendLine($line); $stderrRead=$process.StandardError.ReadLineAsync() }
        }
        if (-not $process.HasExited -and $elapsed.ElapsedMilliseconds -gt $jobTimeoutMs) { $timedOut=$true; $process.Kill(); $process.WaitForExit() }
        Start-Sleep -Milliseconds 20
    }
    $process.WaitForExit(); $stdoutWriter.Dispose(); $stderrWriter.Dispose()
    if ($job.log_pass) {
        @{role='exit_and_log_observation';pass=($process.ExitCode -eq 0 -and $stdoutText.ToString().Contains($job.log_pass));required_log=$job.log_pass;exit_code=$process.ExitCode;timeout=$timedOut} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $jobDir $job.report) -Encoding utf8
    }
    $reportPath = Join-Path $jobDir $job.report
    $report = if (Test-Path -LiteralPath $reportPath) { Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json } else { $null }
    $checkLog = $stdoutText.ToString()+$stderrText.ToString()
    foreach ($expectedError in (@($job.expected_error)+@($job.expected_errors))) {
        if ($expectedError) { $checkLog=[regex]::Replace($checkLog,'(?m)^ERROR: '+[regex]::Escape($expectedError)+'\r?$','') }
    }
    $passed = -not $timedOut -and $process.ExitCode -eq 0 -and $checkLog -notmatch 'SCRIPT ERROR|ERROR:|\bFAIL\b' -and $null -ne $report -and $report.pass -eq $true
    $results += @{job=$job.name;pass=$passed;exit_code=$process.ExitCode;timeout=$timedOut;report=$reportPath;expected_error=$job.expected_error}
}
@{group=$Group;role='shape_brush_verification_run';headless=$headless;commands=$commands;files=$sourceIndex;rendering_driver=$RenderingDriver;gpu_validation_requested=[bool]$GpuValidation;engine_path=$GodotExe;engine_sha256=(Get-FileHash -LiteralPath $GodotExe).Hash.ToLower();engine_version=(& $GodotExe --version | Out-String).Trim();window=if($headless){$null}else{@{width=1280;height=720}};cost_acceptance='not_assessed'} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir 'manifest.json') -Encoding utf8
if ($VulkanImplicitLayerPath) {
    $manifestPath = Join-Path $runDir 'manifest.json'
    $manifestWithLayers = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifestWithLayers | Add-Member -NotePropertyName 'vulkan_implicit_layer_path' -NotePropertyValue $VulkanImplicitLayerPath
    $manifestWithLayers | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
}
$passed = @($results | Where-Object { -not $_.pass }).Count -eq 0
@{pass=$passed;group=$Group;results=$results} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'result.json') -Encoding utf8
$artifacts = foreach ($item in Get-ChildItem -LiteralPath $runDir -Recurse -File) { @{path=$item.FullName;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash.ToLower()} }
$artifacts | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'artifact_index.json') -Encoding utf8
Write-Output $runDir
if (-not $passed) { throw 'Brush verification failed; original evidence retained' }
