param(
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [string]$Engine='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference='Stop'
$projectDirectory=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$ownedProcesses=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -like 'godot*' -and $_.CommandLine -like '*--script*' -and $_.CommandLine -notlike '*--headless*'})
if($ownedProcesses.Count -gt 0){throw 'A visible script probe is already live'}
if(Test-Path -LiteralPath $OutputDirectory){throw 'Fresh output required'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
$sources=@{}
foreach($directory in @('scripts','shaders','assets','scenes','tools/unified_edit_pipeline','tests/integration')){
 Get-ChildItem -LiteralPath (Join-Path $projectDirectory $directory) -File -Recurse |
 Where-Object {$_.Extension -in @('.gd','.glsl','.glslinc','.tres','.tscn','.json','.ps1','.py')} |
 ForEach-Object {$sources[$_.FullName.Substring($projectDirectory.Length+1)]=(Get-FileHash -LiteralPath $_.FullName).Hash}
}
$fixtures=@(
 'g3_profiles_delivery08/water_fill_3',
 'g3_profiles_delivery08/water_wall_3',
 'g3_profiles_delivery08/water_shovel_3',
 'g3_profiles_delivery08/water_split_1',
 'g4_edges_attempt01/water_capacity_1',
 'g4_edges_attempt01/water_many_1'
)
$arguments=@('--path',$projectDirectory,'--script','res://tools/unified_edit_pipeline/audit_cost_probe.gd','--quit-after','7200','--log-file',(Join-Path $OutputDirectory 'probe.log'),'--',('--output='+(Join-Path $OutputDirectory 'probe.json')))
foreach($fixture in $fixtures){$arguments+=('--fixture='+(Join-Path $projectDirectory ('test_output/unified_edit_pipeline/'+$fixture+'/probe.json')))}
$started=Get-Date
& $Engine @arguments 2>&1 | Out-File -LiteralPath (Join-Path $OutputDirectory 'stdout.txt') -Encoding utf8
$exitCode=$LASTEXITCODE
$resultPath=Join-Path $OutputDirectory 'probe.json'
$result=if(Test-Path -LiteralPath $resultPath){Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json}else{$null}
$log=Get-Content -LiteralPath (Join-Path $OutputDirectory 'probe.log') -Raw
$drift=@($sources.Keys | Where-Object {(Get-FileHash -LiteralPath (Join-Path $projectDirectory $_)).Hash -ne $sources[$_]})
$passed=$exitCode -eq 0 -and $null -ne $result -and $result.pass -and $drift.Count -eq 0 -and -not $log.Contains('SCRIPT ERROR:') -and -not $log.Contains("`nERROR:")
@{role='T04 paired GPU audit stages under visible paused main rendering';pass=$passed;exit_code=$exitCode;arguments=$arguments;engine_sha256=(Get-FileHash -LiteralPath $Engine).Hash;started=$started.ToString('o');elapsed_ms=((Get-Date)-$started).TotalMilliseconds;drift=$drift;sources=$sources;result=$resultPath;result_sha256=if($result){(Get-FileHash -LiteralPath $resultPath).Hash}else{''}} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run-manifest.json') -Encoding utf8
Write-Output ('AUDIT_COST '+$passed)
if(-not $passed){exit 1}
