SPA: Post-Quantum KEM + HMAC

Overview
- Control-plane SPA daemon gates WireGuard UDP by inserting a temporary nftables rule after a valid PQ knock.
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
- tag = HMAC(shared_key, PSK || nonce || client_ip || ts)

Operation
- Daemon listens on UDP ${SPA_PQ_PORT}. On valid knock: inserts rule into chain `wg_spa_allow` in `inet filter` and schedules removal after `OPEN_SECS`.
- Nftables: input chain contains `udp dport ${WG_PORT} jump wg_spa_allow`; default DROP remains.
- Client reads JSON config, performs Kyber encapsulation + HMAC, sends single UDP knock, prints OK if acknowledged.

Setup
1. Set in `.env`:
   - SPA_ENABLE=true
   - SPA_MODE=pqkem
   - SPA_PQ_PORT=62201 (default)
   - SPA_PQ_OPEN_SECS=45, SPA_PQ_WINDOW_SECS=30
2. Build tools: `make spa` (optional locally; router will build if needed).
3. Render + apply: `make router`.
4. After deploy, copy `/etc/spa/kem_pub.bin` base64 into `clients/spa-pq-client.json` if not filled.

Client Usage
- Edit `clients/spa-pq-client.json` with `router_host` and verify `kem_pub_b64`/`psk_b64`.
- Run: `cargo run --release --bin spa-pq-client -- --config clients/spa-pq-client.json` (or run the built binary).
- If valid, expect: `OK, port open for N seconds.`

Logging
- Structured JSON to stdout (journal):
  {"ts":"...","client_ip":"...","decision":"allow|deny","reason":"ok|bad_hmac|stale_ts|decap_failed|...","opens_for_secs":45}
- No secrets (keys/psk) are logged.

Testing
- Unit tests cover HMAC composition and time skew checks.
- Integration tests can mock nft via a trait; current MVP schedules real nft rule add/delete.

Notes
- NAT may rewrite source IP; the HMAC includes client_ip as sent by client. If NAT changes the IP, the daemon still binds the allow to the observed src ip.
- Ensure system clock is roughly correct on both sides (NTP recommended).

