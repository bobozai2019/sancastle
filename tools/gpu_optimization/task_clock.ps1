param(
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$Session,
    [ValidateSet('start','finish')][string]$Action = 'start',
    [string]$Decision = '',
    [string]$Reason = ''
)
$clockPath = Join-Path $Session ($TaskId + '_timing.json')
$clockNow = [DateTimeOffset]::Now
$clockTick = [Environment]::TickCount64
if ($Action -eq 'start') {
    if (Test-Path -LiteralPath $clockPath) { throw 'Task clock already exists; do not reset its budget.' }
    $clockRecord = [ordered]@{
        task_id = $TaskId
        started_at = $clockNow.ToOffset([TimeSpan]::FromHours(8)).ToString('o')
        deadline_at = $clockNow.AddMinutes(30).ToOffset([TimeSpan]::FromHours(8)).ToString('o')
        monotonic_started_ms = $clockTick
        finished_at = $null
        elapsed_seconds = $null
        safety_cleanup_seconds = 0
        decision = $null
        reason = $null
    }
} else {
    $clockRecord = Get-Content -LiteralPath $clockPath -Raw | ConvertFrom-Json -AsHashtable
    if ($clockRecord.finished_at) { throw 'Task clock already closed.' }
    $clockRecord.finished_at = $clockNow.ToOffset([TimeSpan]::FromHours(8)).ToString('o')
    $clockRecord.elapsed_seconds = ($clockTick - $clockRecord.monotonic_started_ms) / 1000.0
    $clockRecord.decision = $Decision
    $clockRecord.reason = $Reason
}
$clockRecord | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $clockPath
$clockRecord | ConvertTo-Json -Depth 8
