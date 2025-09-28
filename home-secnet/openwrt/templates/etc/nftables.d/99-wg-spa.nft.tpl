table inet fw4 {
  set wg_spa_allow {
    type ipv4_addr;
    flags timeout;
  }

  chain input_wg_spa_gate {
    type filter hook input priority filter; policy accept;
    # Only allow WireGuard UDP if source IP is in the SPA allow set
    udp dport ${WG_PORT} ip saddr @wg_spa_allow accept
    # default policy for this include chain is accept; the main fw4 input chain
    # still enforces default drop and ordering. This chain only introduces the gate.
  }
}

