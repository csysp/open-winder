OpenWRT Winder (Rearchitecture)

Overview
- This directory contains scripts and templates to build an OpenWRT-based Winder router image with:
  - nftables gate for SPA-gated WireGuard access
  - WireGuard server (`wg0`)
  - AdGuard Home (DNS front) with Unbound (validating upstream)
  - Optional Suricata IDS (disabled by default)

Quick Start
- Prepare env: copy `home-secnet/.env.example` to `home-secnet/.env` and adjust values.
- Render overlay: `make -C home-secnet openwrt-render`
- Build image: `make -C home-secnet openwrt-build`
- Flash (destructive): `make -C home-secnet openwrt-flash device=/dev/sdX image=<image>`

Key Env Vars
- `OPENWRT_VERSION`, `OPENWRT_TARGET`, `OPENWRT_PROFILE`, `OPENWRT_IB_SHA256`
- `LAN_IF`, `WAN_IF` (fallback to `ROUTER_LAN_IF`/`ROUTER_WAN_IF`)
- `NET_TRUSTED`, `GW_TRUSTED` (used for LAN addressing)
- `WG_PORT`, `WG_SERVER_IP`, `WG_SERVER_PRIVKEY`
- `SPA_ENABLE=true`, `SPA_MODE=pqkem`, `SPA_PQ_*` (PSK is auto-generated if missing)

Outputs
- Rendered overlay: `home-secnet/render/openwrt/overlay`
- Built images: `home-secnet/render/openwrt/image`

Notes
- The overlay render does not commit secrets; rendered files live under `render/` (ignored by git).
- If `wg` is not installed locally, the WG private key is left blank and should be provisioned on device.
- IDS is heavy; leave `IDS_ENABLE=false` unless your device has enough RAM/CPU.

