param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$Engine='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe',
    [string[]]$Cases=@('dig','fill','wall','shovel'),
    [string[]]$Patterns=@('straight','corner','overlap'),
    [string[]]$Modes=@('dry_paused','wet_paused','dry_realtime','wet_realtime'),
    [int]$Repeats=1,
    [switch]$Sampling
)
$ErrorActionPreference='Stop'
$projectDirectory=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if(Test-Path -LiteralPath $OutputDirectory){throw 'Fresh output directory required'}
if($Repeats -lt 1){throw 'Repeats must be positive'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$sources=@{}
foreach($directory in @('scripts','shaders','scenes','assets','tools/unified_edit_pipeline')){
    Get-ChildItem -LiteralPath (Join-Path $projectDirectory $directory) -Recurse -File |
        Where-Object {$_.Extension -in @('.gd','.glsl','.gdshader','.tscn','.tres','.json','.bin','.rgba32f','.f32','.ps1','.py')} |
        ForEach-Object {$sources[$_.FullName.Substring($projectDirectory.Length+1)] = (Get-FileHash -LiteralPath $_.FullName).Hash}
}
$sources['project.godot']=(Get-FileHash -LiteralPath (Join-Path $projectDirectory 'project.godot')).Hash
$processes=@(Get-CimInstance Win32_Process -Filter "Name LIKE '%godot%'" | Select-Object ProcessId,Name,ExecutablePath,CommandLine)
$manifest=@{engine=$Engine;engine_sha256=(Get-FileHash -LiteralPath $Engine).Hash;sources=$sources;processes_before=$processes;classification=if($processes.Count){'contended_or_unknown_gpu_activity'}else{'isolated_process_inventory'};sampling=[bool]$Sampling;runs=@();pass=$false;scope='24 samples per case; process-frame completion bounds; full initial footprint validation'}
foreach($case in $Cases){
 if($case -notin @('dig','fill','wall','shovel')){throw 'Unknown case'}
 foreach($pattern in $Patterns){
  if($pattern -notin @('straight','corner','overlap')){throw 'Unknown pattern'}
  foreach($mode in $Modes){
   if($mode -notin @('dry_paused','wet_paused','dry_realtime','wet_realtime')){throw 'Unknown mode'}
   foreach($repeat in 1..$Repeats){
    $name=$case+'_'+$pattern+'_'+$mode+'_'+$repeat
    $resultPath=Join-Path $OutputDirectory ($name+'.json')
    $logPath=Join-Path $OutputDirectory ($name+'.log')
    $engineArguments=@('--path',$projectDirectory,'--rendering-driver','d3d12','--script','res://tools/unified_edit_pipeline/workload_probe.gd','--log-file',$logPath,'--',('--output='+$resultPath),('--case='+$case),('--pattern='+$pattern))
    if($Sampling){$engineArguments+='--sampling'}
    if($mode.StartsWith('wet_')){$engineArguments+='--wet'}
    if($mode.EndsWith('_realtime')){$engineArguments+='--realtime'}
    $started=Get-Date
    & $Engine @engineArguments 2>&1 | Out-File -LiteralPath (Join-Path $OutputDirectory ($name+'.stdout.txt')) -Encoding utf8
    $exitCode=$LASTEXITCODE
    $result=if(Test-Path -LiteralPath $resultPath){Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json}else{$null}
    $drift=@($sources.Keys | Where-Object {(Get-FileHash -LiteralPath (Join-Path $projectDirectory $_)).Hash -ne $sources[$_]})
    $passed=$exitCode -eq 0 -and $null -ne $result -and $result.pass -and $drift.Count -eq 0
    $manifest.runs+=@{name=$name;case=$case;pattern=$pattern;mode=$mode;repeat=$repeat;arguments=$engineArguments;started=$started.ToString('o');elapsed_ms=((Get-Date)-$started).TotalMilliseconds;exit_code=$exitCode;pass=$passed;drift=$drift;result=$resultPath;result_sha256=if($result){(Get-FileHash -LiteralPath $resultPath).Hash}else{''}}
    $manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run-manifest.json') -Encoding utf8
    Write-Output ('RESULT '+$name+' '+$passed)
    if(-not $passed){exit 1}
   }
  }
 }
}
$manifest.pass=$true
$manifest.processes_after=@(Get-CimInstance Win32_Process -Filter "Name LIKE '%godot%'" | Select-Object ProcessId,Name,ExecutablePath,CommandLine)
$manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run-manifest.json') -Encoding utf8
