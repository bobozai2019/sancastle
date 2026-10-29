param([string]$GodotExe = 'D:\godot\Godot_v4.6.2\godot.exe')
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$movie = Join-Path $root 'test_output\sandcastle_visual_reconstruction_phase2\验收\S05_sand_coupled_sequence.avi'
if (Test-Path -LiteralPath $movie) { Remove-Item -LiteralPath $movie }
$output = & $GodotExe --path $root --rendering-driver d3d12 --resolution 1280x720 --fixed-fps 30 --disable-vsync --write-movie $movie --script (Join-Path $PSScriptRoot 'record_sand_coupled.gd') 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Output $output
if ($code -ne 0 -or $output -notmatch 'PASS: S05 sand coupled movie' -or
    $output -match 'SHADER ERROR|SCRIPT ERROR|ERROR:|FAIL:' -or
    -not (Test-Path -LiteralPath $movie) -or
    (Get-Item -LiteralPath $movie).Length -lt 1000000) { exit 1 }
Write-Output ('MOVIE_BYTES=' + (Get-Item -LiteralPath $movie).Length)
exit 0
