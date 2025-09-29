- Security Overview

open-winder aims to reduce exposure rather than increase surface area. The router image defaults to a closed stance and only opens what is required for management and access. WireGuard does not listen to the world by default; Single‑Packet Authorization (SPA) using a post‑quantum KEM plus HMAC briefly opens the WireGuard UDP port after a valid knock. The overlay keeps services bound to localhost where possible, and anything that must listen on the LAN uses OpenWRT’s standard procd and firewall practices.

- Threat Model

The goal is to stop casual and automated scanning on the WAN and to make credential‑spraying on the WireGuard port impractical. The SPA control plane uses ML‑KEM/Kyber‑768 for key agreement and an HMAC over a short window to resist replay. We assume an Internet adversary with the ability to scan and spoof, but not to undetectably rewrite a knock in transit without being noticed by the HMAC and timestamp checks. Data‑plane encryption is provided by WireGuard or Hysteria2 as shipped by OpenWRT; SPA does not change those protocols.

- Secrets and Files

Do not commit secrets. The repository deliberately ignores `home-secnet/.env` and all rendered artifacts under `home-secnet/render/` and `home-secnet/clients/`. During a render the overlay places SPA keys and configuration under `/etc` paths intended for the device, not the repo. If you need local client material, create it under `home-secnet/clients/` on your machine only. Treat `.env` as sensitive; use `home-secnet/.env.example` as the source of truth and copy it locally.

- Defaults and Services

The image favors default‑deny. nftables rules drop unsolicited traffic; SPA inserts time‑limited allow rules only after a valid knock. Auxiliary services (AdGuard Home, Unbound, Suricata) ship with safe bind addresses and can be enabled explicitly through the environment and overlay. Logging avoids secrets and uses OpenWRT’s normal facilities; forward logs consciously if you opt into remote logging.

- Dependencies and Supply Chain

Builds pin OpenWRT releases by tag and expect a checksum for the ImageBuilder archive. Local scripts avoid fetching from moving branches where a tagged release is available. When adding new tooling, prefer tagged releases and document the version and checksum alongside the command that fetches it.

- Reporting a Vulnerability

Please open a private report using GitHub Security Advisories for this repository. If that is not possible for you, open a minimal issue requesting a security contact and do not include sensitive details. We commit to acknowledge reports within three business days and to coordinate a fix or mitigation as quickly as we responsibly can, aiming for disclosure within thirty days when feasible.

- afe‑Harbor

Good‑faith research that stays within your own environments, avoids data exfiltration, and respects service availability is welcome. Do not test against networks you do not own or have permission to assess. If you believe you have found a problem, stop, capture enough detail to reproduce in a lab, and use the reporting channel above.

