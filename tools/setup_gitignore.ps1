# Add local caches, captured data, and downloaded dependencies to the project ignore file.
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$ignorePath = Join-Path $repoRoot '.gitignore'
$start = '# BEGIN sandcastle local-only files'
$end = '# END sandcastle local-only files'
$rules = @'
# Editor and local assistant state
/.godotiq.json
/.claude/
/.codex/
/.shared/
/.mcp.json

# Captures, downloaded game data, and generated results
/rdc/
/rdc_thumbs/
/sandcastlegame/
/test_output/
/logs/

# Local Python packages and caches used by investigation tools
**/__pycache__/
*.py[cod]
**/.venv/
/tests/investigation/brush_hit_competitor/deps/
/tests/investigation/brush_hit_competitor/runtime_collider/deps/
/tests/investigation/brush_hit_competitor/runtime_collider/plot_deps/

# Ad hoc console output
/tests/capture_stdout.txt
/tests/capture_stderr.txt
'@.TrimEnd()

$existing = if (Test-Path -LiteralPath $ignorePath) { [IO.File]::ReadAllText($ignorePath) } else { '' }
$block = "$start`n$rules`n$end"
if ($existing.Contains($start)) {
    $pattern = '(?s)' + [regex]::Escape($start) + '.*?' + [regex]::Escape($end)
    if (-not [regex]::IsMatch($existing, $pattern)) { throw 'Incomplete managed block in .gitignore' }
    $updated = [regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $block }, 1)
} else {
    $updated = $existing.TrimEnd("`r", "`n") + "`n`n" + $block + "`n"
}
if ($updated -ne $existing) {
    [IO.File]::WriteAllText($ignorePath, $updated, [Text.UTF8Encoding]::new($false))
}
Write-Output "Updated $ignorePath"
