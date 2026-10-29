param(
    [string]$GodotExe = 'D:\game\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [switch]$UseExistingCsv
)

if (-not $UseExistingCsv) {
    & (Join-Path $PSScriptRoot 'run_gpu_num09.ps1') -GodotExe $GodotExe -GridSize 256 -Ticks 3600
    if ($LASTEXITCODE -ne 0) { exit 1 }
    & (Join-Path $PSScriptRoot 'run_gpu_num09.ps1') -GodotExe $GodotExe -GridSize 256 -Ticks 3600 -Berm
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

# Build the non-ASCII evidence directory from code points: a raw CJK literal in
# this file breaks under a non-UTF-8 console code page.
$evidenceName = [string][char]0x9A8C + [string][char]0x6536
$evidenceDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot ('../../test_output/sandcastle_water_sand_coupling/' + $evidenceName))).Path
$basePath = Join-Path $evidenceDir 'T04_num09_gpu_256_3600.csv'
$bermPath = Join-Path $evidenceDir 'T04_num09_gpu_256_3600_berm.csv'
$baseLines = Get-Content -LiteralPath $basePath
$bermLines = Get-Content -LiteralPath $bermPath
if ($baseLines.Count -ne 3601 -or $bermLines.Count -ne 3601) {
    Write-Error 'NUM-09 reroute CSV length mismatch'
    exit 1
}
for ($lineIndex = 0; $lineIndex -le 900; $lineIndex++) {
    if ($baseLines[$lineIndex] -cne $bermLines[$lineIndex]) {
        Write-Error "NUM-09 pre-edit histories differ at CSV line $lineIndex"
        exit 1
    }
}
$base = $baseLines | ConvertFrom-Csv
$berm = $bermLines | ConvertFrom-Csv
$shiftedHotspotIntervals = 0
$reroutedFluxIntervals = 0
$maximumHotspotShift = 0.0
$maximumFluxSplitChange = 0.0
foreach ($tick in 1200, 1500, 1800, 2100, 2400, 2700, 3000, 3300, 3600) {
    $a = $base[$tick - 1]
    $b = $berm[$tick - 1]
    $hotspotVolume = [math]::Min([double]$a.interval_hotspot_m3, [double]$b.interval_hotspot_m3)
    $hotspotShift = [double]$b.interval_hotspot_z - [double]$a.interval_hotspot_z
    if ($hotspotVolume -gt 0.001 -and $hotspotShift -gt 0.02) {
        $shiftedHotspotIntervals++
    }
    $maximumHotspotShift = [math]::Max($maximumHotspotShift, $hotspotShift)
    $crossFlux = [math]::Min([double]$a.downstream_cross_flux_m3ps,
        [double]$b.downstream_cross_flux_m3ps)
    $splitChange = [math]::Abs([double]$b.downstream_cross_north_share -
        [double]$a.downstream_cross_north_share)
    if ($crossFlux -gt 0.01) {
        $maximumFluxSplitChange = [math]::Max($maximumFluxSplitChange, $splitChange)
        if ($splitChange -gt 0.10) {
            $reroutedFluxIntervals++
        }
    }
}
$baseFinal = $base[-1]
$bermFinal = $berm[-1]
if ($shiftedHotspotIntervals -lt 3 -or $reroutedFluxIntervals -lt 3 -or
        [double]$baseFinal.downstream_deposit_m3 -lt 0.01 -or
        [double]$bermFinal.downstream_deposit_m3 -lt 0.01) {
    Write-Error "NUM-09 reroute gate failed: hotspot_intervals=$shiftedHotspotIntervals flux_intervals=$reroutedFluxIntervals"
    exit 1
}
Write-Output ('PASS: GPU NUM-09 player berm reroute, identical pre-edit 900 ticks; ' +
    "shifted_hotspot_intervals=$shiftedHotspotIntervals " +
    "rerouted_flux_intervals=$reroutedFluxIntervals " +
    ('max_hotspot_shift={0:F6} max_flux_split_change={1:F6} ' -f
        $maximumHotspotShift, $maximumFluxSplitChange) +
    ('downstream_deposit_base={0:F6} berm={1:F6}' -f
        [double]$baseFinal.downstream_deposit_m3,
        [double]$bermFinal.downstream_deposit_m3))
exit 0
