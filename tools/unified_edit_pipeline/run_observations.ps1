param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$Engine='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe',
    [ValidateSet('workload','visibility','regression','castle')][string]$Suite='workload',
    [string[]]$Cases=@('dig','fill','wall','shovel'),
    [int]$Repeats=1,
    [switch]$Sampling,
    [switch]$Wet,
    [switch]$Realtime
)
$ErrorActionPreference='Stop'
$projectDirectory=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if(Test-Path -LiteralPath $OutputDirectory){throw 'Fresh output required'}
$otherProbes=@(Get-CimInstance Win32_Process -Filter "Name LIKE '%godot%'" | Where-Object {$_.CommandLine -match '--script'})
if($otherProbes.Count){throw 'An existing script probe is still live; wait on its original session.'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$script=if($Suite -eq 'visibility'){'res://tools/unified_edit_pipeline/first_seen_probe.gd'}elseif($Suite -eq 'regression'){'res://tests/integration/async_pipeline_all_tools_probe.gd'}elseif($Suite -eq 'castle'){'res://tools/unified_edit_pipeline/castle_baseline_probe.gd'}else{'res://tools/unified_edit_pipeline/observed_workload_probe.gd'}
if($Suite -eq 'regression'){$Cases=@('all_tools')}
if($Suite -eq 'castle'){$Cases=@('castle')}
$sources=@{}
foreach($directory in @('scripts','shaders','scenes','assets','tools/unified_edit_pipeline','tests/integration')){
 Get-ChildItem -LiteralPath (Join-Path $projectDirectory $directory) -Recurse -File |
 Where-Object {$_.Extension -in @('.gd','.glsl','.gdshader','.tscn','.tres','.json','.bin','.rgba32f','.f32','.ps1','.py')} |
 ForEach-Object {$sources[$_.FullName.Substring($projectDirectory.Length+1)]=(Get-FileHash -LiteralPath $_.FullName).Hash}
}
$sources['project.godot']=(Get-FileHash -LiteralPath (Join-Path $projectDirectory 'project.godot')).Hash
$manifest=@{suite=$Suite;sampling=[bool]$Sampling;engine=$Engine;engine_sha256=(Get-FileHash -LiteralPath $Engine).Hash;sources=$sources;processes_before=@(Get-CimInstance Win32_Process -Filter "Name LIKE '%godot%'" | Select-Object ProcessId,Name,CommandLine);classification='contended_or_unknown_gpu_activity';runs=@();pass=$false}
foreach($repeat in 1..$Repeats){
 foreach($case in $Cases){
  if($case -notin @('dig','fill','wall','shovel') -and $Suite -notin @('regression','castle')){throw 'Unknown case'}
  $name=$Suite+'_'+$case+'_'+$repeat
  $resultPath=Join-Path $OutputDirectory ($name+'.json')
  $logPath=Join-Path $OutputDirectory ($name+'.log')
  $engineArguments=@('--path',$projectDirectory,'--rendering-driver','d3d12','--script',$script,'--log-file',$logPath,'--',('--output='+$resultPath),('--case='+$case))
  if($Sampling){$engineArguments+='--sampling'}
  if($Wet){$engineArguments+='--wet'}
  if($Realtime){$engineArguments+='--realtime'}
  $started=Get-Date
  & $Engine @engineArguments 2>&1 | Out-File -LiteralPath (Join-Path $OutputDirectory ($name+'.stdout.txt')) -Encoding utf8
  $exitCode=$LASTEXITCODE
  $result=if(Test-Path -LiteralPath $resultPath){Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json}else{$null}
  $drift=@($sources.Keys | Where-Object {(Get-FileHash -LiteralPath (Join-Path $projectDirectory $_)).Hash -ne $sources[$_]})
  $passed=$exitCode -eq 0 -and $null -ne $result -and $result.pass -and $drift.Count -eq 0
  $manifest.runs+=@{name=$name;case=$case;repeat=$repeat;arguments=$engineArguments;started=$started.ToString('o');elapsed_ms=((Get-Date)-$started).TotalMilliseconds;exit_code=$exitCode;pass=$passed;drift=$drift;result=$resultPath;result_sha256=if($result){(Get-FileHash -LiteralPath $resultPath).Hash}else{''}}
  $manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run-manifest.json') -Encoding utf8
  Write-Output ('RESULT '+$name+' '+$passed)
  if(-not $passed){exit 1}
 }
}
$manifest.pass=$true
$manifest.processes_after=@(Get-CimInstance Win32_Process -Filter "Name LIKE '%godot%'" | Select-Object ProcessId,Name,CommandLine)
$manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run-manifest.json') -Encoding utf8
