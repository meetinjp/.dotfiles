#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    throw 'setup.ps1 writes to HKLM and must be run from an elevated PowerShell. Open PowerShell as Administrator and rerun.'
}

Write-Host 'Running one-shot machine setup...'

# Remap Caps Lock -> Left Ctrl via the keyboard scancode map.
# Takes effect after sign-out / reboot. Survives reboots; only needs to run once.
$kbLayout = 'HKLM:\System\CurrentControlSet\Control\Keyboard Layout'
$desired  = [byte[]](@(
    '00','00','00','00','00','00','00','00',
    '02','00','00','00',
    '1d','00','3a','00',
    '00','00','00','00'
) | ForEach-Object { [byte]('0x' + $_) })

$existing = (Get-ItemProperty -Path $kbLayout -Name 'Scancode Map' -ErrorAction SilentlyContinue).'Scancode Map'
if ($existing -and -not (Compare-Object $existing $desired)) {
    Write-Host 'Caps Lock -> Ctrl remap: already applied.'
} else {
    New-ItemProperty -Path $kbLayout -Name 'Scancode Map' -PropertyType Binary -Value $desired -Force | Out-Null
    Write-Host 'Caps Lock -> Ctrl remap: applied (sign out / reboot for it to take effect).'
}

Write-Host 'Machine setup complete!'
