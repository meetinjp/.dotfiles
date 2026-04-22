#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

$Dotfiles = $PSScriptRoot

# ---------------------------------------------------------------------------
# 1. Install prerequisites via winget (idempotent)
#
# These are needed so Mason (inside nvim) can install language servers that
# depend on them:
#   - Python   → ruff, python-lsp-server, clang-format (mason installs via pip)
#   - Go       → gopls (mason installs via `go install`)
#   - Rustup   → optional; for rustc/cargo when editing Rust (rust-analyzer
#                itself is installed by Mason as a prebuilt binary)
#   - ripgrep  → used by Telescope live_grep / grep_string
#   - zig      → C compiler used by nvim-treesitter (master branch) to build
#                parsers locally. Picked over LLVM/mingw for size (~60MB) and
#                because nvim-treesitter's cc detection already handles `zig`.
# ---------------------------------------------------------------------------

$Prereqs = @(
    @{ Id = 'Python.Python.3.12';      Override = 'InstallAllUsers=0 PrependPath=1 Include_launcher=1' },
    @{ Id = 'GoLang.Go';               Override = $null },
    @{ Id = 'Rustlang.Rustup';         Override = $null },
    @{ Id = 'BurntSushi.ripgrep.MSVC'; Override = $null },
    @{ Id = 'zig.zig';                 Override = $null }
)

if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host 'Ensuring prerequisites are installed via winget...'
    foreach ($p in $Prereqs) {
        $listed = & winget list --exact --id $p.Id --disable-interactivity --accept-source-agreements 2>&1
        if ($listed -match 'No installed package') {
            $installArgs = @(
                'install', '--exact', '--id', $p.Id,
                '--silent',
                '--accept-package-agreements', '--accept-source-agreements',
                '--source', 'winget',
                '--disable-interactivity'
            )
            if ($p.Override) { $installArgs += @('--override', $p.Override) }
            & winget @installArgs | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  $($p.Id): installed"
            } else {
                Write-Warning "  $($p.Id): winget exit $LASTEXITCODE (continuing)"
            }
        } else {
            Write-Host "  $($p.Id): already installed"
        }
    }
} else {
    Write-Warning 'winget not found — skipping prerequisite installation.'
}

# ---------------------------------------------------------------------------
# 2. Link config directories via junctions (no admin required)
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# 3. PowerShell profile stub
#
# $PROFILE can't be a junction (single file) and a symlink would need admin,
# so we write a tiny stub that dot-sources the repo profile.
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# 4. Claude Code config
#
# ~/.claude.json is live-mutated by Claude itself (auth, project history,
# caches), so we can't junction or symlink it. Patch the specific keys we
# want enforced instead.
# ---------------------------------------------------------------------------

& (Join-Path $Dotfiles 'claude\apply.ps1')

# ---------------------------------------------------------------------------
# 5. gminds — separate (eventually public) repo, brought in as a submodule.
# Delegates to its own installer so install logic lives with the tool
# (junctions skill into ~/.claude/skills/gminds, drops ~/.local/bin/gminds.cmd,
# winget-installs Zellij if missing).
# ---------------------------------------------------------------------------

$GMindsInstaller = Join-Path $Dotfiles 'gminds\install.ps1'
if (Test-Path -LiteralPath $GMindsInstaller) {
    & $GMindsInstaller
} else {
    Write-Warning 'gminds submodule missing — run: git submodule update --init'
}

Write-Host 'Dotfiles installed successfully!'
Write-Host 'Open a new PowerShell session so PATH changes take effect, then run `nvim` to let Mason install the remaining language servers.'
