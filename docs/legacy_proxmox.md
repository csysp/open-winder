Legacy Proxmox/Ubuntu VM Flow (Deprecated Here)

This branch focuses on the OpenWRT image + overlay approach for Winder. The previous Proxmox/Ubuntu VM automation is deprecated in this branch and not supported by default.

Notes
- Environment variable `MODE` defaults to `openwrt` and scripts will fail if set otherwise.
- For history and prior automation details, consult the `legacy/proxmox` branch or the tagged snapshot `legacy-proxmox-v0`.

Migration
- Prefer moving to the OpenWRT build with overlayed Winder components.
- If you must operate the legacy flow temporarily, use the legacy branch and do not mix artifacts across branches.

