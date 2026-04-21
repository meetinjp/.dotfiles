#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

$Dotfiles = $PSScriptRoot

$Links = @(
    @{ Source = Join-Path $Dotfiles 'nvim\.config\nvim';         Target = Join-Path $env:LOCALAPPDATA 'nvim' },
    @{ Source = Join-Path $Dotfiles 'prettier\.config\prettier'; Target = Join-Path $env:USERPROFILE '.config\prettier' }
)

Write-Host 'Installing dotfiles...'

foreach ($link in $Links) {
    $src = $link.Source
    $dst = $link.Target

    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warning "Source missing, skipping: $src"
        continue
    }

    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $dst) {
        $existing = Get-Item -LiteralPath $dst -Force
        $isReparse = ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        if (-not $isReparse) {
            Write-Warning "Target exists and is not a link: $dst — move or remove it, then rerun."
            continue
        }
        # Safe for reparse points: removes the junction itself, not its target.
        [IO.Directory]::Delete($dst)
    }

    New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
    Write-Host "Linked: $dst -> $src"
}

Write-Host 'Dotfiles installed successfully!'
