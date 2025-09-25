SPA: Post-Quantum KEM + HMAC

Overview
- PQ-KEM SPA is the default SPA mode in Winder. The control-plane SPA daemon gates WireGuard UDP by inserting a temporary nftables allow rule after a valid post-quantum knock.
- Uses ML-KEM/Kyber-768 for key agreement and HMAC-SHA256 for authentication over a short-lived window.
- Data plane (WireGuard/Hysteria2) remains unchanged.

Threat Model
- Prevent opportunistic scanning and volumetric credential spraying on UDP/WG port.
- Resist quantum adversaries against the control plane by using ML-KEM-768.
- Assumes attacker cannot MITM and rewrite knock contents without detection; timestamp window reduces replay.
- Keys and PSK are stored locally on the router under /etc/spa with strict permissions.

Packet Format
- ct_len: u16 (BE)
- ct: [u8; ct_len] (Kyber768 ciphertext)
- nonce: [u8; 16]
- ts: i64 (unix seconds, BE)
- client_ip_v4: u32 (network order)
- tag: [u8; 32] (HMAC-SHA256)
- tag = HMAC(shared_key, PSK || ver || nonce || ts)

Operation
- Daemon listens on UDP ${SPA_PQ_PORT}. On valid knock: inserts rule into chain `wg_spa_allow` in `table inet filter` and schedules removal after `OPEN_SECS`.
- Nftables: input chain contains `udp dport ${WG_PORT} jump wg_spa_allow`; default DROP remains.
- Client reads JSON config, performs Kyber encapsulation + HMAC, sends single UDP knock, prints OK if acknowledged.

Setup
1. Set in `.env`:
   - SPA_ENABLE=true
   - SPA_MODE=pqkem
   - SPA_PQ_PORT=62201 (default)
   - SPA_PQ_OPEN_SECS=45, SPA_PQ_WINDOW_SECS=30
2. Build tools: `make spa` (optional locally; the router will build if needed).
3. Render + apply: `make router`.
4. After deploy, if `kem_pub_b64` is not yet filled in `clients/spa-pq-client.json`, read `/etc/spa/kem_pub.bin` on the router and base64-encode it locally into the JSON.

Client Usage
- Edit `clients/spa-pq-client.json` with `router_host` and verify `kem_pub_b64`/`psk_b64`.
- Run: `cargo run --manifest-path home-secnet/clients/spa-pq-client/Cargo.toml --release -- --config clients/spa-pq-client.json` (or run the built binary).
- If valid, expect: `OK, port open for N seconds.`

Logging
- Structured JSON to stdout (journal):
  {"ts":"...","client_ip":"...","decision":"allow|deny","reason":"ok|bad_hmac|stale_ts|decap_failed|...","opens_for_secs":45}
- No secrets (keys/psk) are logged.

Log Reasons
- ok: Valid knock, IP allowed for open_secs.
- ok_nat_mismatch: Valid knock; client_ip in packet differs from observed src (likely NAT).
- bad_ver: Unsupported packet version.
- bad_ct_len: Ciphertext length not equal to Kyber768 size (1088).
- length mismatch: Total packet length inconsistent with header.
- stale_ts: Timestamp outside configured window.
- replay: (src_ip, nonce, ts) seen within TTL; rejected.
- decap_failed: Ciphertext failed to decapsulate with provided KEM secret.
- hmac_key: Internal HMAC key error.
- bad_hmac: HMAC verification failed.

Operational Checks
- nftables: confirm table/chain/set exist before starting the daemon:
  - `nft list table inet filter`
  - `nft list chain inet filter wg_spa_allow`
  - `nft list set inet filter wg_spa_allow_set`
- Time sync: ensure NTP is running on router and clients.
- SPA port: verify the UDP port is listening: `ss -ulnp | grep :$SPA_PQ_PORT`
- Logs: journalctl -u winder-spa-pq -o cat | jq '.'

Systemd Install Flow (Template)
1. Copy sources to router host: `/opt/router/spa-pq-src`
2. Build and install binary:
   - `home-secnet/router/systemd/spa-pq/install-spa-pq.sh`
3. Prepare `/etc/spa/` secrets and permissions:
   - `/etc/spa/kem_priv.bin` (0600), `/etc/spa/kem_pub.bin` (0644), PSK file (0600)
4. Ensure nftables objects exist (ExecStartPre in unit handles this by default)
5. Render unit from template and enable:
   - `envsubst < home-secnet/router/systemd/spa-pq/spa-pq.service.template | sudo tee /etc/systemd/system/winder-spa-pq.service`
   - `sudo systemctl daemon-reload && sudo systemctl enable --now winder-spa-pq`

Testing
- Unit tests cover HMAC composition and time skew checks.
- Integration tests can mock nft via a trait; current MVP schedules real nft rule add/delete.

Notes
- NAT may rewrite source IP; the daemon always binds the allow to the observed source IP. client_ip is carried in the packet for diagnostics only and is NOT included in HMAC.
- Ensure system clock is roughly correct on both sides (NTP recommended).
