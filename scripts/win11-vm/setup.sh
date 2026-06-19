#!/usr/bin/env bash
# Minimal-footprint Windows 11 VM for Okta Verify + Chrome on niri/CachyOS.
# Designed for: TUXEDO InfinityBook Pro 14 (AMD Gen10) — single AMD iGPU used for virgl.
# Target footprint: ~14 GB disk used / 64 GB sparse, ~2 GB RAM ballooned, 2 vCPU.
# Win11 hard requires: UEFI + Secure Boot + TPM 2.0. All wired up here.
#
# Usage:
#   ./setup.sh                          # interactive, prompts for ISO path
#   ISO=/path/to/win11.iso ./setup.sh   # non-interactive

set -euo pipefail

# ─── CONFIG ──────────────────────────────────────────────────────────────────
VM_NAME="${VM_NAME:-win11-okta}"
VM_DIR="${VM_DIR:-$HOME/vms}"
DISK_PATH="$VM_DIR/${VM_NAME}.qcow2"
DISK_SIZE_GB="${DISK_SIZE_GB:-64}"
RAM_MB="${RAM_MB:-4096}"
VCPUS="${VCPUS:-2}"
RENDER_NODE="${RENDER_NODE:-/dev/dri/renderD128}"   # AMD iGPU (single-GPU box; verify: ls -l /dev/dri/by-path/)
VIRTIO_WIN_ISO="$VM_DIR/virtio-win.iso"
VIRTIO_WIN_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
# Bluetooth USB passthrough. Set BT_USB="vendor:product" (e.g. 0489:e0e4) or
# leave empty to skip. Find yours with: lsusb | grep -i wireless
# Note: while VM runs, the Linux host loses access to this BT device.
BT_USB="${BT_USB:-}"

bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# ─── STEP 1: PACKAGES ────────────────────────────────────────────────────────
bold "[1/6] Installing packages (sudo will prompt)…"
PKGS=(qemu-full libvirt virt-manager edk2-ovmf swtpm dnsmasq iptables-nft virtiofsd)
MISSING=()
for p in "${PKGS[@]}"; do
    pacman -Q "$p" &>/dev/null || MISSING+=("$p")
done
if (( ${#MISSING[@]} )); then
    sudo pacman -S --needed --noconfirm "${MISSING[@]}"
else
    green "    all packages present."
fi

# ─── STEP 2: SERVICES + GROUPS + FIREWALL ────────────────────────────────────
bold "[2/6] Enabling libvirt + adding user to groups…"
sudo systemctl enable --now libvirtd.service
sudo systemctl enable --now virtlogd.socket || true
for g in libvirt kvm; do
    id -nG "$USER" | tr ' ' '\n' | grep -qx "$g" || sudo usermod -aG "$g" "$USER"
done
if ! sudo virsh net-info default &>/dev/null; then
    red "    default libvirt network missing — start virt-manager once to seed it."
fi
sudo virsh net-autostart default 2>/dev/null || true
sudo virsh net-start default 2>/dev/null || true

# UFW (CachyOS default) drops DHCP from virbr0 → guest stays APIPA. Allow it.
if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    yellow "    UFW active — opening virbr0 for guest DHCP/DNS + NAT forwarding."
    sudo ufw allow in on virbr0 >/dev/null
    sudo ufw route allow in on virbr0 >/dev/null
    sudo ufw default allow FORWARD >/dev/null
    sudo ufw reload >/dev/null
fi

# ─── STEP 3: ISO PATH ────────────────────────────────────────────────────────
bold "[3/6] Locating Windows 11 ISO…"
if [[ -z "${ISO:-}" ]]; then
    yellow "    Get one from:"
    echo   "      Win11 (official, direct ISO on Linux UA): https://www.microsoft.com/software-download/windows11"
    read -rp "Path to Win11 ISO: " ISO
fi
[[ -f "$ISO" ]] || { red "ISO not found: $ISO"; exit 1; }
green "    ISO: $ISO"

# ─── STEP 4: VIRTIO-WIN DRIVERS ──────────────────────────────────────────────
bold "[4/6] Fetching virtio-win driver ISO…"
mkdir -p "$VM_DIR"
if [[ ! -f "$VIRTIO_WIN_ISO" ]]; then
    curl -L --fail -o "$VIRTIO_WIN_ISO" "$VIRTIO_WIN_URL"
else
    green "    already present: $VIRTIO_WIN_ISO"
fi

# ─── STEP 5: DISK ────────────────────────────────────────────────────────────
bold "[5/6] Creating qcow2 disk…"
if [[ -f "$DISK_PATH" ]]; then
    yellow "    $DISK_PATH already exists — leaving it alone."
else
    qemu-img create -f qcow2 -o cluster_size=64K,extended_l2=on,preallocation=off \
        "$DISK_PATH" "${DISK_SIZE_GB}G"
    green "    created: $DISK_PATH (${DISK_SIZE_GB}G sparse)"
fi

# ─── STEP 6: VIRT-INSTALL ────────────────────────────────────────────────────
bold "[6/6] Creating VM via virt-install…"
if virsh --connect qemu:///system dominfo "$VM_NAME" &>/dev/null; then
    yellow "    VM '$VM_NAME' already defined — skipping virt-install."
    yellow "    Start with: virt-manager  (or virsh start $VM_NAME)"
    exit 0
fi

# System-mode libvirt runs qemu as libvirt-qemu user. Grant traverse + read on
# the paths we hand it. Disk dir needs rw so qemu can write the qcow2.
ISO_DIR="$(dirname "$ISO")"
sudo setfacl -m u:libvirt-qemu:x "$HOME" 2>/dev/null || true
sudo setfacl -m u:libvirt-qemu:x "$ISO_DIR" 2>/dev/null || true
sudo setfacl -R -m u:libvirt-qemu:rwX "$VM_DIR" 2>/dev/null || true
sudo setfacl -m u:libvirt-qemu:r "$ISO" 2>/dev/null || true

# Render node access for virgl
if [[ -e "$RENDER_NODE" ]]; then
    sudo setfacl -m u:libvirt-qemu:rw "$RENDER_NODE" 2>/dev/null || true
fi

VIRT_INSTALL_ARGS=(
    --connect qemu:///system
    --name "$VM_NAME"
    --osinfo win11
    --machine q35
    --cpu "host-passthrough,topology.sockets=1,topology.cores=${VCPUS},topology.threads=1"
    --vcpus "$VCPUS"
    --memory "memory=$RAM_MB,currentMemory=$RAM_MB"
    --memballoon model=virtio
    # Win11 needs UEFI Secure Boot. SMM is required for Secure Boot to function.
    --boot firmware=efi,loader.secure=yes
    --features smm.state=on
    --tpm model=tpm-crb,backend.type=emulator,backend.version=2.0
    --disk "path=$DISK_PATH,bus=virtio,format=qcow2,discard=unmap,cache=none"
    --disk "path=$ISO,device=cdrom,readonly=on"
    --disk "path=$VIRTIO_WIN_ISO,device=cdrom,readonly=on"
    --network network=default,model=virtio
    --graphics "spice,gl.enable=yes,listen=none,rendernode=$RENDER_NODE"
    --video model=virtio,accel3d=yes
    --sound none
    --controller type=usb,model=qemu-xhci
    --rng /dev/urandom
    --noautoconsole
)
if [[ -n "$BT_USB" ]]; then
    # virt-install's --hostdev parser has no 'managed' suboption; use xpath override.
    VIRT_INSTALL_ARGS+=(--hostdev "$BT_USB,xpath.set=./@managed=yes")
    yellow "    Bluetooth USB '$BT_USB' will be passed through (host loses BT when VM runs)."
fi
virt-install "${VIRT_INSTALL_ARGS[@]}"

green ""
green "VM '$VM_NAME' created."
green ""
if [[ -z "$BT_USB" ]]; then
    yellow "Tip: to add Bluetooth later, find your USB id with 'lsusb' (look for Wireless_Device / btusb),"
    yellow "     then shut the VM down and attach raw XML — see README.md §8.5."
fi
bold "Next: open virt-manager, connect to the VM's display, follow README.md."
