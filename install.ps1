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

# Install PowerShell profile stub. $PROFILE can't be a junction (single file) and
# a symlink would need admin, so we write a tiny stub that dot-sources the repo.
$ProfileSource = Join-Path $Dotfiles 'powershell\profile.ps1'
$ProfileStub = ". `"$ProfileSource`""
$profileParent = Split-Path -Parent $PROFILE
if (-not (Test-Path -LiteralPath $profileParent)) {
    New-Item -ItemType Directory -Path $profileParent -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $PROFILE)) {
    Set-Content -LiteralPath $PROFILE -Value $ProfileStub -Encoding UTF8
    Write-Host "Stubbed profile: $PROFILE"
} elseif ((Get-Content -LiteralPath $PROFILE -Raw) -like "*$ProfileSource*") {
    Write-Host "Profile stub already present: $PROFILE"
} else {
    Write-Warning "Profile exists and isn't stubbed: $PROFILE — add this line manually:`n  $ProfileStub"
}

Write-Host 'Dotfiles installed successfully!'
