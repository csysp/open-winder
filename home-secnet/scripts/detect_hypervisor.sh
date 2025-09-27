#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'

# Purpose: Detect common hypervisors and print setup steps (read-only)
# Inputs: none
# Outputs: human-readable hints for Hyper-V, VirtualBox, and KVM
# Side effects: none (read-only)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_LOG="$SCRIPT_DIR/lib/log.sh"
if [[ -f "$LIB_LOG" ]]; then
  # shellcheck disable=SC1090
  source "$LIB_LOG"
else
  log_info() { echo "[info] $*"; }
  log_warn() { echo "[warn] $*" >&2; }
  die() { echo "[error] $*" >&2; exit 1; }
fi

has() { command -v "$1" >/dev/null 2>&1; }
kernel_has_module() { lsmod 2>/dev/null | awk '{print $1}' | grep -qx "$1"; }

detected="none"
detail=()

# Prefer systemd-detect-virt if available
if has systemd-detect-virt; then
  vtype=$(systemd-detect-virt 2>/dev/null || true)
  case "$vtype" in
    kvm)
      detected="kvm" ;;
    microsoft|hyperv)
      detected="hyperv" ;;
    oracle|virtualbox)
      detected="virtualbox" ;;
  esac
fi

# Heuristics if still unknown
if [[ "$detected" == "none" ]]; then
  if has virsh || has virt-install || kernel_has_module kvm; then detected="kvm"; fi
fi
if [[ "$detected" == "none" ]]; then
  if has VBoxManage || kernel_has_module vboxdrv; then detected="virtualbox"; fi
fi
if [[ "$detected" == "none" ]]; then
  if kernel_has_module hv_vmbus || kernel_has_module hv_netvsc; then detected="hyperv"; fi
fi

log_info "Detected hypervisor: ${detected}"

case "$detected" in
  hyperv)
    cat <<'HYPERV'
Next steps (Hyper-V host on Windows):
1) Enable Hyper-V (Admin PowerShell):
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
2) Create vSwitches:
   # External (WAN): bound to your physical NIC
   New-VMSwitch -Name WAN-External -NetAdapterName 'Ethernet' -AllowManagementOS $true -EnableIov $false
   # Internal (LAN): host-only network for LAN side
   New-VMSwitch -Name LAN-Internal -SwitchType Internal
3) Create VM (Gen2, UEFI, Secure Boot OFF) and attach vNICs:
   Set-VMFirmware -VMName open-winder -EnableSecureBoot Off
   Add-VMNetworkAdapter -VMName open-winder -SwitchName WAN-External -Name wan0
   Add-VMNetworkAdapter -VMName open-winder -SwitchName LAN-Internal -Name lan0
   Set-VMNetworkAdapter -VMName open-winder -Name lan0 -MacAddressSpoofing On
4) Boot Ubuntu 24.04, run the host setup, then `make router`.
Refs: https://learn.microsoft.com/windows-server/virtualization/hyper-v/hyper-v-networking
HYPERV
    ;;
  virtualbox)
    cat <<'VBOX'
Next steps (VirtualBox host):
1) Create networks:
   - Adapter 1: NAT (WAN) or Bridged to your physical NIC
   - Adapter 2: Host-only network (LAN); set Promiscuous Mode: Allow All
2) VM settings:
   - Paravirtualization: KVM
   - Chipset: Q35, EFI enabled
   - NICs: virtio-net if available (or Paravirtualized Network)
3) Boot Ubuntu 24.04, run the host setup, then `make router`.
Refs: https://www.virtualbox.org/manual/ch06.html
VBOX
    ;;
  kvm)
    cat <<'KVM'
Next steps (Linux KVM/libvirt host):
1) Ensure packages installed:
   sudo apt-get install -y qemu-kvm libvirt-daemon-system virtinst bridge-utils
2) Create bridges (example):
   # Using nmcli (adjust ifnames)
   sudo nmcli connection add type bridge ifname wanbr con-name wanbr
   sudo nmcli connection add type ethernet ifname <wan-nic> master wanbr
   sudo nmcli connection add type bridge ifname lanbr con-name lanbr
   # Attach <lan-nic> or use isolated bridge for LAN
3) Create VM with 2 virtio NICs attached to wanbr and lanbr:
   virt-install --name open-winder --memory 4096 --vcpus 2 \
     --disk size=16 --os-variant ubuntu24.04 --cdrom ubuntu-24.04-live-server-amd64.iso \
     --network bridge=wanbr,model=virtio --network bridge=lanbr,model=virtio \
     --graphics none --boot uefi
4) After install, run the host setup and `make router`.
Refs: https://wiki.libvirt.org/page/Networking
KVM
    ;;
  *)
    log_warn "No known hypervisor detected. See README for provider-agnostic setup."
    ;;
esac

