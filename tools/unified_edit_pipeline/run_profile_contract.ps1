param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$Engine='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference='Stop'
$projectDirectory=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if(Test-Path -LiteralPath $OutputDirectory){throw 'Fresh output required'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$sources=@{}
foreach($directory in @('scripts/simulation/unified_edit','assets/unified_edit')){
 Get-ChildItem -LiteralPath (Join-Path $projectDirectory $directory) -File |
 ForEach-Object {$sources[$_.FullName.Substring($projectDirectory.Length+1)]=(Get-FileHash -LiteralPath $_.FullName).Hash}
}
foreach($relative in @('tests/integration/unified_edit_profile_probe.gd','tests/integration/unified_edit_foreign_profile.gd','assets/brushes/castle/four_towers_v1.rgba32f')){
 $sources[$relative]=(Get-FileHash -LiteralPath (Join-Path $projectDirectory $relative)).Hash
}
$resultPath=Join-Path $OutputDirectory 'probe.json'
$logPath=Join-Path $OutputDirectory 'probe.log'
$engineArguments=@('--headless','--path',$projectDirectory,'--script','res://tests/integration/unified_edit_profile_probe.gd','--log-file',$logPath,'--',('--output='+$resultPath))
$started=Get-Date
& $Engine @engineArguments 2>&1 | Out-File -LiteralPath (Join-Path $OutputDirectory 'stdout.txt') -Encoding utf8
$exitCode=$LASTEXITCODE
$result=if(Test-Path -LiteralPath $resultPath){Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json}else{$null}
$drift=@($sources.Keys | Where-Object {(Get-FileHash -LiteralPath (Join-Path $projectDirectory $_)).Hash -ne $sources[$_]})
$passed=$exitCode -eq 0 -and $null -ne $result -and $result.pass -and $drift.Count -eq 0
$manifest=@{role='headless T01 profile data contract only';engine=$Engine;engine_sha256=(Get-FileHash -LiteralPath $Engine).Hash;arguments=$engineArguments;started=$started.ToString('o');elapsed_ms=((Get-Date)-$started).TotalMilliseconds;exit_code=$exitCode;pass=$passed;drift=$drift;sources=$sources;checks=if($result){$result.checks.Count}else{0};result=$resultPath;result_sha256=if($result){(Get-FileHash -LiteralPath $resultPath).Hash}else{''}}
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run-manifest.json') -Encoding utf8
Write-Output ('PROFILE_CONTRACT '+$passed+' checks='+$manifest.checks)
if(-not $passed){exit 1}
