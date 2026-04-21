# PowerShell profile — sourced from $PROFILE by install.ps1.
# Keep additions small; prefer per-project config over per-shell.

# Prepend ~/.local/bin to PATH (used by Claude Code CLI and other local tools).
$LocalBin = Join-Path $env:USERPROFILE '.local\bin'
if ((Test-Path -LiteralPath $LocalBin) -and ($env:PATH -notlike "*$LocalBin*")) {
    $env:PATH = "$LocalBin;$env:PATH"
}
