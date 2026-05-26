# Win11 VM for Okta Verify + Chrome

Minimal Windows 11 (64-bit) VM. Purpose: run Okta Verify (FastPass) + Chrome on
Linux when your org's Okta policy requires the Windows desktop client.

## Footprint

- Disk: 64 GB sparse qcow2, ~14 GB used after install + Chrome + Okta Verify.
  qcow2 sparse: idle cost on host is the *used* bytes, not the 64 GB ceiling.
  Override with `DISK_SIZE_GB=N` env var before running `setup.sh`.
- RAM: 4 GB allocated, ~1.5–2 GB used after balloon (Win11 needs more than Win10).
- vCPU: 2 cores (host-passthrough, no emulation overhead)
- GPU: virgl on AMD iGPU (`renderD129`); NVIDIA RTX 4060 left untouched
- Win11 hard requirements satisfied: UEFI + Secure Boot + TPM 2.0 (swtpm).
- Support: in-support until 2031 (24H2) — long-term stable.

### Resizing later

```sh
sudo virsh shutdown win11-okta
sudo qemu-img resize ~/vms/win11-okta.qcow2 +15G
sudo virsh start win11-okta
# Inside Win11 (elevated PowerShell):
#   "rescan" | diskpart
#   # If a Recovery partition sits after C:, delete it first:
#   #   @"
#   #   select disk 0
#   #   select partition 4
#   #   delete partition override
#   #   exit
#   #   "@ | diskpart
#   $max = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
#   Resize-Partition -DriveLetter C -Size $max
```

## Step 1 — Download Windows 11 ISO

Direct link (Linux UA → no form): <https://www.microsoft.com/software-download/windows11>

- Scroll to "Download Windows 11 Disk Image (ISO) for x64 devices"
- Select edition: **Windows 11 (multi-edition)** → Download
- Language → English → Confirm
- Click **64-bit Download** → save as `~/Downloads/win11.iso` (~6 GB)

(From a Windows browser MS hides the ISO link and pushes the Media Creation
Tool — Linux UA shows the ISO directly.)

## Step 2 — Run the host-side script

```sh
ISO=~/Downloads/win11.iso ~/.dotfiles/scripts/win11-vm/setup.sh
```

Script installs packages, enables libvirt, opens UFW for `virbr0` (DHCP/DNS +
forwarding so the guest can reach the internet), applies the ACLs that let
`libvirt-qemu` read your ISO/disk under `$HOME`, downloads virtio-win drivers,
creates the disk, defines the VM (`win11-okta`) with UEFI Secure Boot + TPM 2.0.

If you were just added to `libvirt` / `kvm` groups: log out + back in, or
`newgrp libvirt`, then re-run.

## Step 3 — Boot the installer

```sh
virt-manager
```

Open `win11-okta` → monitor icon → boot reaches the Windows installer.

1. Language / keyboard → Next → Install now.
2. "I don't have a product key" → Next.
3. Edition: **Windows 11 Pro** (Home will force MS-account sign-in).
4. Accept license → Custom: Install Windows only.
5. Disk list is empty (no virtio driver loaded). Click **Load driver** →
   Browse → CD drive labelled **virtio-win** → `viostor\w11\amd64` → OK →
   pick `Red Hat VirtIO SCSI controller`. Disk appears.
6. Select it → Next. Install proceeds. VM reboots.

> Win11 setup may complain about TPM / Secure Boot only if those aren't wired
> up; this script wires both, so the check passes silently.

## Step 4 — Skip Microsoft account at OOBE

Win11 makes this harder than Win10.

1. Region: pick anything → Next.
2. Keyboard → Next → Skip 2nd keyboard.
3. At "Let's connect you to a network" or sign-in screen, press **Shift+F10**
   → cmd opens. Run:
   ```
   start ms-cxh:localonly
   ```
   A "Create local account" dialog appears (works on Win11 24H2+). Fill it in.
   - Older 23H2 ISOs: use `oobe\BypassNRO.cmd` instead (forces a reboot).
   - If neither works: in virt-manager, unplug NIC link state for the duration of OOBE, then re-enable.
4. Privacy toggles → turn all OFF → Accept.
5. Reach desktop. Re-enable NIC if you disabled it.

## Step 5 — Install virtio guest tools (better perf + balloon)

Open Explorer → CD drive **virtio-win** → run `virtio-win-guest-tools.exe` →
Next → Install. Reboot when prompted. This activates the balloon driver
(reclaims unused RAM to Linux host) and SPICE clipboard sharing.

## Step 6 — Debloat (elevated PowerShell)

Right-click Start → Terminal (Admin) → PowerShell:

```powershell
powercfg /h off
Set-Service -Name SysMain -StartupType Disabled -ErrorAction SilentlyContinue
Set-Service -Name WSearch -StartupType Disabled -ErrorAction SilentlyContinue
sc.exe config "DiagTrack" start=disabled
wmic computersystem set AutomaticManagedPagefile=False
wmic pagefileset where "name='C:\\pagefile.sys'" set InitialSize=512,MaximumSize=512
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -Value 2
# Kill Win11-specific bloat too:
Get-AppxPackage -AllUsers Microsoft.GetHelp        | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers Microsoft.YourPhone      | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers MicrosoftTeams           | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers Microsoft.WindowsFeedbackHub | Remove-AppxPackage -ErrorAction SilentlyContinue
Restart-Computer -Force
```

## Step 7 — Install Chrome + Okta Verify

```powershell
winget install --silent --accept-package-agreements --accept-source-agreements Google.Chrome
winget install --silent --accept-package-agreements --accept-source-agreements Okta.OktaVerify
```

If `winget` is missing / errors, fall back:

- Chrome: <https://www.google.com/chrome/> — download `.exe`, install.
- Okta Verify: sign in to `https://<your-company>.okta.com` → Settings →
  Extra Verification → Set up Okta Verify → "Want to use it on your computer?"
  → download the Windows installer your tenant offers.

(If your tenant doesn't expose a self-serve download, ask IT for the MSI.)

## Step 8 — Enrol Okta Verify

1. Open Okta Verify.
2. Sign in: `https://<company>.okta.com`.
3. Set up FastPass — Windows Hello (PIN inside VM) registers a passkey backed
   by the virtual TPM 2.0.
4. Done.

## Step 8.5 — Bluetooth (optional)

Internal laptop BT is a USB device — pass it through to the VM. Trade-off:
**while the VM is running, the Linux host loses BT** (managed mode auto-detaches
on VM start, auto-reattaches on VM stop). USB devices cannot be shared
concurrently between host and guest — for "both at once" you need a second
adapter (cheap USB BT dongle works).

Find the USB id of the BT controller:

```sh
lsusb | grep -iE 'wireless|bluetooth'
# Example output: Bus 001 Device 002: ID 0489:e0e4 Foxconn / Hon Hai Wireless_Device
```

`vendor:product` is the `ID` field (e.g. `0489:e0e4`).

### If the VM already exists

`virt-xml` doesn't accept the `managed=` suboption — attach raw XML instead.
Substitute your `vendor` / `product` hex IDs:

```sh
sudo virsh shutdown win11-okta
cat <<'EOF' | sudo virsh attach-device --config win11-okta /dev/stdin
<hostdev mode='subsystem' type='usb' managed='yes'>
  <source>
    <vendor id='0x0489'/>
    <product id='0xe0e4'/>
  </source>
</hostdev>
EOF
sudo virsh start win11-okta
```

### If creating fresh

```sh
BT_USB=0489:e0e4 ISO=~/Downloads/win11.iso ~/.dotfiles/scripts/win11-vm/setup.sh
```

### Inside Win11

- Settings → Bluetooth & devices → toggle ON.
- If "no Bluetooth adapter": Device Manager → unknown device → Update driver → Windows Update. Or download MediaTek MT7922 Bluetooth driver from your laptop vendor's support page.

### Verifying separation from WiFi

Most laptops have a combo M.2 card (MT7922 / Intel AX211 / etc) but the WiFi
side is a **PCI device** and the BT side is a **USB device**. Confirm before
passing through:

```sh
lspci | grep -i wireless     # WiFi (PCI) — stays on Linux
lsusb | grep -i wireless     # BT  (USB)  — passes to VM
```

If WiFi shows up under `lsusb`, your hardware is unusual; do not pass through
or you lose WiFi too.

## Step 9 — Reach your Linux dev server from the VM

libvirt NAT exposes the Linux host at **`192.168.122.1`**. Chrome in the VM
→ `http://192.168.122.1:3000` (or whatever port). Okta FastPass loopback stays
inside the VM; dev app served from Linux host.

## Step 10 — Daily usage

Add to your `~/.config/zsh/aliases.zsh` (or wherever):

```sh
alias vmsave='virsh --connect qemu:///system save win11-okta ~/vms/win11-okta.save'
alias vmrestore='virsh --connect qemu:///system restore ~/vms/win11-okta.save'
alias vmstart='virsh --connect qemu:///system start win11-okta && virt-viewer --connect qemu:///system win11-okta &'
alias vmstop='virsh --connect qemu:///system shutdown win11-okta'
```

- `vmsave` — dumps RAM to disk, frees host RAM.
- `vmrestore` — back in ~3 s.
- `vmstart` + `vmstop` — cold boot/shutdown.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `virt-install` complains about firmware | `pacman -S edk2-ovmf`. |
| `Permission denied` on qcow2 / ISO when starting VM | system-mode libvirt runs qemu as `libvirt-qemu`, which can't traverse `$HOME` by default. `setup.sh` applies the ACLs automatically; if you create new disks/ISOs by hand: `sudo setfacl -m u:libvirt-qemu:x $HOME && sudo setfacl -R -m u:libvirt-qemu:rwX $HOME/vms && sudo setfacl -m u:libvirt-qemu:r /path/to/iso`. |
| VM gets `169.254.x.x` (APIPA), no DHCP | UFW is dropping DHCP from `virbr0`. `setup.sh` opens it automatically; if you re-enable UFW later: `sudo ufw allow in on virbr0 && sudo ufw route allow in on virbr0 && sudo ufw default allow FORWARD && sudo ufw reload`. Then **fully shut down and restart the VM** (not just `ipconfig /renew`) — after `virsh net-destroy/net-start`, the NIC port needs to rebind, which only happens on VM restart. |
| No reply to DHCP DISCOVER on `virbr0` (tcpdump shows only Requests) | Same UFW root cause. Verify with `sudo nft list ruleset \| grep -A5 'chain INPUT'` — policy `drop` + ufw chains = UFW. Apply the fix above. |
| `network port not found: ... does not exist` in libvirtd log | Stale port after `net-destroy/net-start`. Restart the VM (`sudo virsh shutdown win11-okta && sudo virsh start win11-okta`) — don't only renew DHCP. |
| `Resize-Partition: The partition is already the requested size` | Recovery partition sits after C: and blocks growth. Run `Get-Partition -DiskNumber 0`; if a `Recovery` partition is present, drop it: `@"select disk 0`<br>`select partition 4`<br>`delete partition override`<br>`exit"@ \| diskpart` — then resize C:. |
| Black screen / virgl errors | virt-manager → VM → Hardware → Display Spice → OpenGL off (loses GPU offload). |
| Disk not found during install | Skipped Step 3.5 — re-run with virtio driver load (`viostor\w11\amd64`). |
| OOBE forces MS-account sign-in | Press Shift+F10 → `start ms-cxh:localonly` (24H2+) or `oobe\BypassNRO.cmd` (older). Or unplug the NIC link in virt-manager. |
| Okta Verify "device unmanaged" | Org requires SCEP / device-trust onboarding link from IT. |
| Slow display | Confirm `gl.enable=yes` in `<graphics spice>` + `accel3d='yes'` in `<video>`. `setfacl -m u:libvirt-qemu:rw /dev/dri/renderD129`. |
| Win11 nags about activation | Ignore. Watermark only. Personalisation locked but irrelevant for this use. |
