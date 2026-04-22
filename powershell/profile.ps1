# PowerShell profile — sourced from $PROFILE by install.ps1.
# Keep additions small; prefer per-project config over per-shell.

# Prepend ~/.local/bin to PATH (used by Claude Code CLI and other local tools).
$LocalBin = Join-Path $env:USERPROFILE '.local\bin'
if ((Test-Path -LiteralPath $LocalBin) -and ($env:PATH -notlike "*$LocalBin*")) {
    $env:PATH = "$LocalBin;$env:PATH"
}

if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -EditMode Vi
}

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    # Theme checked into repo so this works regardless of which oh-my-posh
    # install variant is on PATH (Store build ships no themes; winget build
    # sets POSH_THEMES_PATH but may be shadowed by the Store alias).
    $PoshTheme = Join-Path $PSScriptRoot 'robbyrussell.omp.json'
    oh-my-posh init pwsh --config $PoshTheme | Invoke-Expression
}
