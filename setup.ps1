#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

$Dotfiles = $PSScriptRoot

# --- Locate gpg (prefer Git for Windows bundle, then PATH) ---
$gpg = $null
if (Test-Path -LiteralPath 'C:\Program Files\Git\usr\bin\gpg.exe') {
    $gpg = 'C:\Program Files\Git\usr\bin\gpg.exe'
} else {
    $gpgCmd = Get-Command gpg -ErrorAction SilentlyContinue
    if ($gpgCmd) { $gpg = $gpgCmd.Source }
}
if (-not $gpg) {
    throw 'gpg not found. Install Git for Windows (bundles gpg) or GnuPG and rerun.'
}
if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
    throw 'ssh-keygen not found. Enable Windows OpenSSH Client (Settings -> Apps -> Optional features) and rerun.'
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git not found. Install Git for Windows and rerun.'
}

# --- Install git config templates ---
Write-Host 'Installing git config templates...'
$gitconfigSrc     = Join-Path $Dotfiles 'git\.gitconfig'
$gitconfigWorkSrc = Join-Path $Dotfiles 'git\.gitconfig-work'
$gitconfigDst     = Join-Path $env:USERPROFILE '.gitconfig'
$gitconfigWorkDst = Join-Path $env:USERPROFILE '.gitconfig-work'
Copy-Item -Force -LiteralPath $gitconfigSrc     -Destination $gitconfigDst
Copy-Item -Force -LiteralPath $gitconfigWorkSrc -Destination $gitconfigWorkDst

$personalEmail = (& git config --file $gitconfigDst     user.email).Trim()
$workEmail     = (& git config --file $gitconfigWorkDst user.email).Trim()
$gitName       = (& git config --file $gitconfigDst     user.name).Trim()

Write-Host "  name:      $gitName"
Write-Host "  personal:  $personalEmail"
Write-Host "  work:      $workEmail (auto on repos under ~/work/lunar/)"
Write-Host ''

function Get-GpgKeyId {
    param([string]$EmailOrUid)
    $line = & $gpg --list-secret-keys --with-colons $EmailOrUid 2>$null |
        Where-Object { $_ -like 'sec:*' } |
        Select-Object -First 1
    if ($line) { return $line.Split(':')[4] } else { return $null }
}

# --- SSH key ---
$sshDir = Join-Path $env:USERPROFILE '.ssh'
$sshKey = Join-Path $sshDir 'id_ed25519'
if (Test-Path -LiteralPath $sshKey) {
    Write-Host "SSH key already at $sshKey - skipping."
} else {
    $ans = Read-Host 'Generate Ed25519 SSH key? [Y/n]'
    if ($ans -notmatch '^[nN]') {
        if (-not (Test-Path -LiteralPath $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir | Out-Null
        }
        ssh-keygen -t ed25519 -C $personalEmail -f $sshKey
        Write-Host ''
        Write-Host 'Add this SSH public key at https://github.com/settings/ssh/new'
        Write-Host '------------------------------------------------------------'
        Get-Content -LiteralPath "$sshKey.pub"
        Write-Host '------------------------------------------------------------'
        Write-Host ''
    }
}

# --- GPG key ---
$keyid = Get-GpgKeyId -EmailOrUid $personalEmail
if ($keyid) {
    Write-Host "GPG key for $personalEmail already exists (keyid=$keyid) - using it."
} else {
    $ans = Read-Host 'Generate Ed25519 GPG signing key (2y, with both email UIDs)? [Y/n]'
    if ($ans -notmatch '^[nN]') {
        & $gpg --quick-gen-key "meetinjp <$personalEmail>" ed25519 default 2y
        $keyid = Get-GpgKeyId -EmailOrUid $personalEmail
        if (-not $keyid) { throw 'GPG key generation appeared to fail - no secret key found.' }
        & $gpg --quick-add-uid $keyid "meetinjp <$workEmail>"
        Write-Host ''
        Write-Host 'Add this GPG public key at https://github.com/settings/gpg/new'
        Write-Host '------------------------------------------------------------'
        & $gpg --armor --export $keyid
        Write-Host '------------------------------------------------------------'
        Write-Host ''
    }
}

if ($keyid) {
    & git config --global user.signingkey $keyid
    & git config --global gpg.program $gpg
}

# --- Caps Lock -> Ctrl (admin-required one-shot; self-elevates) ---
$kbLayout   = 'HKLM:\System\CurrentControlSet\Control\Keyboard Layout'
$desiredMap = [byte[]]@(0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x1d,0x00,0x3a,0x00,0x00,0x00,0x00,0x00)
$currentMap = (Get-ItemProperty -Path $kbLayout -Name 'Scancode Map' -ErrorAction SilentlyContinue).'Scancode Map'

if ($currentMap -and -not (Compare-Object $currentMap $desiredMap)) {
    Write-Host 'Caps Lock -> Ctrl remap: already applied.'
} else {
    $ans = Read-Host 'Remap Caps Lock -> Ctrl? Needs admin, will trigger UAC [Y/n]'
    if ($ans -notmatch '^[nN]') {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isAdmin) {
            New-ItemProperty -Path $kbLayout -Name 'Scancode Map' -PropertyType Binary -Value $desiredMap -Force | Out-Null
            Write-Host 'Caps Lock -> Ctrl remap: applied (sign out / reboot to take effect).'
        } else {
            $adminBlock = @'
$kbLayout   = 'HKLM:\System\CurrentControlSet\Control\Keyboard Layout'
$desiredMap = [byte[]]@(0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x1d,0x00,0x3a,0x00,0x00,0x00,0x00,0x00)
New-ItemProperty -Path $kbLayout -Name 'Scancode Map' -PropertyType Binary -Value $desiredMap -Force | Out-Null
Write-Host 'Caps Lock -> Ctrl remap: applied (sign out / reboot to take effect).'
Write-Host 'Press Enter to close...' -NoNewline
[void][Console]::ReadLine()
'@
            $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
            Start-Process $shell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',$adminBlock
            Write-Host 'Elevated window launched for the Caps Lock remap - accept the UAC prompt.'
        }
    }
}

Write-Host ''
Write-Host 'Setup complete.'
