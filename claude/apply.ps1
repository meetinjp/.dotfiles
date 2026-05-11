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

# --- Claude Code plugins ---------------------------------------------------
# Install Claude Code plugins user-globally so they survive across all sessions
# (including every Lunar tab) without per-session boot work. Idempotent: skips
# when the marketplace is already registered and the plugin cache dir exists.

function Ensure-ClaudePlugin {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Marketplace,
        [Parameter(Mandatory)][string]$Plugin
    )
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Host "claude CLI not on PATH - skipping $Plugin install."
        return
    }
    $known = Join-Path $HOME '.claude\plugins\known_marketplaces.json'
    $hasMarketplace = $false
    if (Test-Path -LiteralPath $known) {
        $hasMarketplace = (Get-Content -LiteralPath $known -Raw) -match "`"$Marketplace`""
    }
    if (-not $hasMarketplace) {
        Write-Host "Adding Claude marketplace $Marketplace from $Source..."
        & claude plugin marketplace add $Source
    }
    $cache = Join-Path $HOME ".claude\plugins\cache\$Marketplace\$Plugin"
    if (-not (Test-Path -LiteralPath $cache)) {
        Write-Host "Installing Claude plugin $Plugin@$Marketplace..."
        & claude plugin install "$Plugin@$Marketplace" --scope user
    } else {
        Write-Host "Claude plugin ${Plugin}@${Marketplace}: already installed."
    }
}

# Each call: -Source <github owner/name | url | path>  -Marketplace <name>  -Plugin <name>
Ensure-ClaudePlugin -Source 'JuliusBrussee/caveman' -Marketplace 'caveman' -Plugin 'caveman'
