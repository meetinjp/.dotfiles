#!/usr/bin/env pwsh
# Idempotently merge dotfiles-managed Claude Code config keys into
# ~/.claude.json. Claude Code live-mutates that file, so we can't junction or
# symlink it — we reconcile the specific keys we care about instead.
#
# Works on both Windows PowerShell 5.1 and PowerShell 7+, so it stays callable
# from install.ps1 regardless of which host the user launches it with.
$ErrorActionPreference = 'Stop'

$Desired = @{
    editorMode = 'vim'
}

$Path = Join-Path $HOME '.claude.json'

if (Test-Path -LiteralPath $Path) {
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $data = [pscustomobject]@{}
    } else {
        try {
            $data = $raw | ConvertFrom-Json
        } catch {
            Write-Error "error: $Path is not valid JSON: $_"
            exit 1
        }
        if ($data -isnot [pscustomobject]) {
            Write-Error "error: $Path is not a JSON object"
            exit 1
        }
    }
} else {
    $data = [pscustomobject]@{}
}

$changed = @()
foreach ($key in $Desired.Keys) {
    $value = $Desired[$key]
    $existing = $data.PSObject.Properties[$key]
    if ($null -eq $existing) {
        $data | Add-Member -NotePropertyName $key -NotePropertyValue $value
        $changed += $key
    } elseif ($existing.Value -ne $value) {
        $existing.Value = $value
        $changed += $key
    }
}

if ($changed.Count -gt 0) {
    $tmp = "$Path.tmp"
    $json = $data | ConvertTo-Json -Depth 100
    # Use UTF-8 without BOM to match Claude Code's own writes.
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
    Write-Host "updated ${Path}: set $($changed -join ', ')"
} else {
    Write-Host "${Path}: already up to date"
}
