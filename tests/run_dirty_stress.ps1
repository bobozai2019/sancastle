param(
    [int]$Runs = 50,
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'gpu_dirty_chunk_probe.gd'
$samples = [System.Collections.Generic.List[object]]::new()
for ($run = 1; $run -le $Runs; $run++) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotExe
    $startInfo.Arguments = '--path "' + $projectPath + '" --rendering-driver d3d12 --script "' + $scriptPath + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) {
        $process.Kill()
        Write-Error "Dirty-chunk run $run timed out"
        exit 1
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    if ($process.ExitCode -ne 0 -or $stdout -notmatch 'PASS: packed 1/4/16 dirty chunks' -or
            ($stdout + $stderr) -match 'SCRIPT ERROR|ERROR:|FAIL:') {
        Write-Output $stdout
        if ($stderr) { Write-Output $stderr }
        Write-Error "Dirty-chunk run $run failed"
        exit 1
    }
    $matches = [regex]::Matches($stdout, 'CHUNKS=(1|4|16) GPU_TO_CPU_MS=([0-9.]+) COLLISION_REPLACE_MS=([0-9.]+)')
    if ($matches.Count -ne 3) {
        Write-Error "Dirty-chunk run $run did not contain three timings"
        exit 1
    }
    $rayMatch = [regex]::Match($stdout, 'CHUNKS=16 GPU_TO_RAY_MS=([0-9.]+)')
    if (-not $rayMatch.Success) {
        Write-Error "Dirty-chunk run $run did not contain ray latency"
        exit 1
    }
    foreach ($match in $matches) {
        $rayValue = $null
        if ([int]$match.Groups[1].Value -eq 16) {
            $rayValue = [double]::Parse($rayMatch.Groups[1].Value, [cultureinfo]::InvariantCulture)
        }
        $samples.Add([pscustomobject]@{
            run = $run
            chunks = [int]$match.Groups[1].Value
            gpu_to_cpu_ms = [double]::Parse($match.Groups[2].Value, [cultureinfo]::InvariantCulture)
            collision_replace_ms = [double]::Parse($match.Groups[3].Value, [cultureinfo]::InvariantCulture)
            gpu_to_ray_ms = $rayValue
        })
    }
    if ($run % 10 -eq 0) { Write-Output "DIRTY_STRESS completed=$run/$Runs" }
}
$evidenceName = [string][char]0x9A8C + [string][char]0x6536
$evidenceDir = Join-Path $projectPath ('test_output\sandcastle_water_sand_coupling\' + $evidenceName)
$csvPath = Join-Path $evidenceDir 'T00_dirty_chunk_stress_20260928.csv'
$samples | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
foreach ($chunkCount in @(1, 4, 16)) {
    $subset = @($samples | Where-Object { $_.chunks -eq $chunkCount })
    $metrics = @('gpu_to_cpu_ms', 'collision_replace_ms')
    if ($chunkCount -eq 16) { $metrics += 'gpu_to_ray_ms' }
    foreach ($metric in $metrics) {
        $ordered = @($subset | ForEach-Object { $_.$metric } | Sort-Object)
        $p50 = $ordered[[math]::Max(0, [math]::Ceiling(0.50 * $ordered.Count) - 1)]
        $p95 = $ordered[[math]::Max(0, [math]::Ceiling(0.95 * $ordered.Count) - 1)]
        $p99 = $ordered[[math]::Max(0, [math]::Ceiling(0.99 * $ordered.Count) - 1)]
        Write-Output ('DIRTY_STATS chunks={0} metric={1} n={2} p50={3:F3} p95={4:F3} p99={5:F3} max={6:F3}' -f
            $chunkCount, $metric, $ordered.Count, $p50, $p95, $p99, $ordered[-1])
    }
}
Write-Output "PASS: $Runs repeated 1/4/16 dirty-chunk probes"
exit 0
