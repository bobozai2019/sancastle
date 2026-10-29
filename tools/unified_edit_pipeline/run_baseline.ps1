param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$Engine='D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe',
    [string[]]$Cases=@('dig','fill','wall','shovel'),
    [switch]$Sampling
)
$ErrorActionPreference='Stop'
$projectDirectory=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (Test-Path -LiteralPath $OutputDirectory) {throw 'Use a fresh output directory.'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$sources=@{}
foreach ($directory in @('scripts','shaders','scenes','assets','tools/unified_edit_pipeline')) {
    Get-ChildItem -LiteralPath (Join-Path $projectDirectory $directory) -Recurse -File |
        Where-Object {$_.Extension -in @('.gd','.glsl','.gdshader','.tscn','.tres','.json','.bin','.ps1','.py')} |
        ForEach-Object {$sources[$_.FullName.Substring($projectDirectory.Length+1)] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
}
$sources['project.godot']=(Get-FileHash -LiteralPath (Join-Path $projectDirectory 'project.godot')).Hash
$processes=@(Get-CimInstance Win32_Process -Filter "Name LIKE '%godot%'" | Select-Object ProcessId,Name,ExecutablePath,CommandLine)
$manifest=@{engine=$Engine;engine_sha256=(Get-FileHash -LiteralPath $Engine).Hash;sources=$sources;processes_before=$processes;classification=if($processes.Count){'contended_or_unknown_gpu_activity'}else{'isolated_process_inventory'};sampling=[bool]$Sampling;runs=@();pass=$false;scope='G0 exploratory 20-command paused straight-path samples; not full baseline gate'}
foreach ($case in $Cases) {
    if ($case -notin @('dig','fill','wall','shovel')) {throw 'Unknown baseline case'}
    $resultPath=Join-Path $OutputDirectory ($case+'.json')
    $logPath=Join-Path $OutputDirectory ($case+'.log')
    $engineArguments=@('--path',$projectDirectory,'--rendering-driver','d3d12','--script','res://tools/unified_edit_pipeline/baseline_profile.gd','--log-file',$logPath,'--',('--output='+$resultPath),('--case='+$case))
    if ($Sampling) {$engineArguments+='--sampling'}
    $started=Get-Date
    & $Engine @engineArguments 2>&1 | Out-File -LiteralPath (Join-Path $OutputDirectory ($case+'.stdout.txt')) -Encoding utf8
    $exitCode=$LASTEXITCODE
    $result=if(Test-Path -LiteralPath $resultPath){Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json}else{$null}
    $drift=@($sources.Keys | Where-Object {(Get-FileHash -LiteralPath (Join-Path $projectDirectory $_)).Hash -ne $sources[$_]})
    $passed=$exitCode -eq 0 -and $null -ne $result -and $result.pass -and $drift.Count -eq 0
    $manifest.runs+=@{case=$case;arguments=$engineArguments;started=$started.ToString('o');elapsed_ms=((Get-Date)-$started).TotalMilliseconds;exit_code=$exitCode;pass=$passed;drift=$drift;result=$resultPath;result_sha256=if($result){(Get-FileHash -LiteralPath $resultPath).Hash}else{''}}
    $manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run-manifest.json') -Encoding utf8
    Write-Output ('RESULT '+$case+' '+$passed)
    if(-not $passed){exit 1}
}
$manifest.pass=$true
$manifest.processes_after=@(Get-CimInstance Win32_Process -Filter "Name LIKE '%godot%'" | Select-Object ProcessId,Name,ExecutablePath,CommandLine)
$manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run-manifest.json') -Encoding utf8
