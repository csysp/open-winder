table inet fw4 {
  set wg_spa_allow {
    type ipv4_addr;
    flags timeout;
  }

  chain input {
    # Only allow WireGuard UDP if source IP is in the SPA allow set
    udp dport ${WG_PORT} ip saddr @wg_spa_allow accept
  }
}
