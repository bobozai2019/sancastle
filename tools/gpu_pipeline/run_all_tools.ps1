param(
    [string]$OutputDirectory = '',
    [string]$Engine = 'D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe',
    [string[]]$Only = @()
)
$ErrorActionPreference = 'Stop'
$projectDirectory = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $OutputDirectory) {$OutputDirectory = Join-Path $projectDirectory ('test_output/all_tools_pipeline/run_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))}
if (Test-Path -LiteralPath (Join-Path $OutputDirectory 'run-manifest.json')) {throw 'Use a fresh output directory; existing evidence is preserved.'}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$cases = @(
    @{name='tools_main';script='async_pipeline_all_tools_probe.gd';args=@()},
    @{name='tools_capture';script='async_pipeline_all_tools_probe.gd';args=@('--scene=res://scenes/playable/test1_capture.tscn')},
    @{name='tools_backwash';script='async_pipeline_all_tools_probe.gd';args=@('--scene=res://scenes/playable/test1_backwash.tscn')},
    @{name='main_regression';script='async_pipeline_main_probe.gd';args=@('--tools','--ui')},
    @{name='tool_upload';script='async_pipeline_tools_fault_probe.gd';args=@('--case=upload')},
    @{name='tool_register';script='async_pipeline_tools_fault_probe.gd';args=@('--case=register')},
    @{name='tool_unknown';script='async_pipeline_tools_fault_probe.gd';args=@('--case=unknown')},
    @{name='tool_bad_identity';script='async_pipeline_tools_fault_probe.gd';args=@('--case=tool_identity')},
    @{name='tool_bad_tick';script='async_pipeline_tools_fault_probe.gd';args=@('--case=tool_tick')},
    @{name='ordinary_unknown';script='async_pipeline_fault_probe.gd';args=@('--case=unknown')},
    @{name='public_suspended';script='async_pipeline_public_api_probe.gd';args=@('--case=suspended')},
    @{name='partial_bootstrap';script='async_pipeline_bootstrap_fault_probe.gd';args=@('--case=bootstrap-visuals')},
    @{name='candidate_cleanup';script='async_pipeline_candidate_fault_probe.gd';args=@('--case=candidate-unknown')},
    @{name='checkpoint';script='async_pipeline_checkpoint_probe.gd';args=@()},
    @{name='tools_boundary';script='async_pipeline_tools_boundary_probe.gd';args=@()},
    @{name='play';script='async_pipeline_tools_play_probe.gd';args=@()},
    @{name='water_full';script='async_pipeline_water_probe.gd';args=@('--coupled','--mold','--boundary','--visuals')}
)
if ($Only.Count) {$cases = @($cases | Where-Object {$_.name -in $Only})}
$sources = @{}
foreach ($relativeDirectory in @('scripts/beach','scripts/simulation/edit_validation/frame_pipeline')) {
    Get-ChildItem -LiteralPath (Join-Path $projectDirectory $relativeDirectory) -File |
        Where-Object { $_.Extension -in @('.gd','.glsl') } |
        ForEach-Object { $sources[$_.FullName.Substring($projectDirectory.Length+1).Replace('\','/')] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$manifest = @{date='2026-10-17';engine=$Engine;engine_sha256=(Get-FileHash -LiteralPath $Engine -Algorithm SHA256).Hash.ToLowerInvariant();sources=$sources;runs=@();pass=$false}
foreach ($case in $cases) {
    $resultPath = Join-Path $OutputDirectory ($case.name+'.json')
    $logPath = Join-Path $OutputDirectory ($case.name+'.log')
    if ((Test-Path -LiteralPath $resultPath) -or (Test-Path -LiteralPath $logPath)) {throw ('Existing case evidence: '+$case.name)}
    $engineArguments = @('--path',$projectDirectory,'--rendering-driver','d3d12','--script',('res://tests/integration/'+$case.script),'--log-file',$logPath,'--',('--output='+$resultPath)) + $case.args
    $start = Get-Date
    Write-Output ('RUN '+$case.name)
    & $Engine @engineArguments 2>&1 | Out-File -LiteralPath (Join-Path $OutputDirectory ($case.name+'.stdout.txt')) -Encoding utf8
    $exitCode = $LASTEXITCODE
    $result = if (Test-Path -LiteralPath $resultPath) {Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json} else {$null}
    $passed = $exitCode -eq 0 -and $null -ne $result -and $result.pass
    $drift = @($sources.Keys | Where-Object {(Get-FileHash -LiteralPath (Join-Path $projectDirectory $_) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sources[$_]})
    $passed = $passed -and $drift.Count -eq 0
    $manifest.runs += @{name=$case.name;arguments=$engineArguments;exit_code=$exitCode;pass=$passed;source_drift=$drift;checks=@($result.checks).Count;elapsed_ms=[math]::Round(((Get-Date)-$start).TotalMilliseconds,3);result=$resultPath;result_sha256=if($result){(Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()}else{''}}
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run-manifest.json') -Encoding utf8
    Write-Output ('RESULT '+$case.name+' '+$passed+' checks='+@($result.checks).Count)
    if (-not $passed) {exit 1}
}
$manifest.pass = $true
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run-manifest.json') -Encoding utf8
Write-Output ('PASS '+$manifest.runs.Count+' runs')
