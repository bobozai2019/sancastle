param([Parameter(Mandatory=$true)][string]$RunDir)
$trace = Get-Content -LiteralPath (Join-Path $RunDir 'trace.json') -Raw | ConvertFrom-Json
$frames = Get-Content -LiteralPath (Join-Path $RunDir 'frames.json') -Raw | ConvertFrom-Json
$commands = Get-Content -LiteralPath (Join-Path $RunDir 'commands.json') -Raw | ConvertFrom-Json
$runtime = Get-Content -LiteralPath (Join-Path $RunDir 'runtime.json') -Raw | ConvertFrom-Json
function Stats($values) {
    $sorted = @($values | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    return @{count=$sorted.Count; p50=$sorted[[math]::Ceiling($sorted.Count*0.5)-1]; p99=$sorted[[math]::Ceiling($sorted.Count*0.99)-1]; max=$sorted[-1]}
}
$rows = foreach ($command in $commands) {
    $id = $command.command_id
    $stages = @{}
    foreach ($event in $trace) {
        if ($event.ids -contains $id) { $stages[$event.stage] = $event.us }
    }
    $published = @($trace | Where-Object { $_.stage -eq 'collision_publish_end' -and $_.ids -contains $id })
    $dispatch = @($trace | Where-Object { $_.stage -eq 'patch_cpu_dispatch_end' -and $_.detail.revision -eq $published[0].detail })
    $completion = @($trace | Where-Object { $_.stage -eq 'patch_readback_completion_upper_bound' -and $_.detail.serial -eq $dispatch[0].detail.serial })
    $gpuUpper = if ($dispatch.Count -eq 1 -and $completion.Count -eq 1) { ($completion[0].us-$dispatch[0].us)/1000 } else { $null }
    [pscustomobject]@{command_id=$id; kind=$command.kind; submit_us=$command.submit_us;
        cpu_tool_ms=($stages.cpu_tool_end-$stages.cpu_tool_begin)/1000;
        collision_ms=($stages.collision_publish_end-$stages.collision_publish_begin)/1000;
        patch_dispatch_to_readback_upper_bound_ms=$gpuUpper;
        submit_to_post_draw_ms=($stages.first_post_draw_after_revision-$command.submit_us)/1000}
}
$near = @(); $far = @()
foreach ($frame in $frames) {
    $isNear = $false
    foreach ($command in $commands) {
        if ([math]::Abs($frame.us-$command.submit_us) -le 100000) { $isNear=$true; break }
    }
    if ($isNear) { $near += $frame.frame_ms } else { $far += $frame.frame_ms }
}
$missing = @('pixel_confirmed_visibility')
if (-not ($trace.stage -contains 'sand_readback_request')) { $missing += 'exact_prefetch_request' }
if (-not ($trace.stage -contains 'patch_cpu_dispatch_begin')) { $missing += 'gpu_patch_submit' }
if (-not ($trace.stage -contains 'patch_readback_completion_upper_bound')) { $missing += 'gpu_patch_completion_upper_bound' }
if (-not (Test-Path -LiteralPath (Join-Path $RunDir 'initial_domain.bin'))) { $missing += 'initial_state_binary' }
$summary = @{role='diagnostic_analysis'; cost_acceptance='not_evaluated';
    all_frame_ms=(Stats $frames.frame_ms); edit_near_100ms_frame_ms=(Stats $near);
    other_frame_ms=(Stats $far); cpu_tool_ms=(Stats $rows.cpu_tool_ms);
    collision_ms=(Stats $rows.collision_ms); submit_to_post_draw_ms=(Stats $rows.submit_to_post_draw_ms);
    patch_dispatch_to_readback_upper_bound_ms=(Stats @($rows.patch_dispatch_to_readback_upper_bound_ms | Where-Object { $null -ne $_ }));
    completed_tick_callbacks=@($trace | Where-Object { $_.stage -eq 'tick_completed_callback' -and $_.us -ge $runtime.start_us -and $_.us -le $runtime.end_us }).Count;
    missing=$missing;
    limitation='post_draw is the first draw following CPU revision callback; it does not independently confirm changed pixels. Frame intervals include diagnostic overhead; no cost PASS.'}
$rows | Export-Csv -LiteralPath (Join-Path $RunDir 'command_metrics.csv') -NoTypeInformation -Encoding utf8
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $RunDir 'analysis.json') -Encoding utf8
$trace | Sort-Object us | ForEach-Object { [pscustomobject]@{us=$_.us;stage=$_.stage;ids=($_.ids | ConvertTo-Json -Compress);detail=($_.detail | ConvertTo-Json -Depth 5 -Compress)} } | Export-Csv -LiteralPath (Join-Path $RunDir 'trace.csv') -NoTypeInformation -Encoding utf8
$frames | Export-Csv -LiteralPath (Join-Path $RunDir 'frames.csv') -NoTypeInformation -Encoding utf8
$summary | ConvertTo-Json -Depth 8
