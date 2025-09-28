bind_host: 0.0.0.0
bind_port: 53
schema_version: 27
users: []
http:
  address: ${ADGUARD_UI_LISTEN}
dns:
  upstream_dns:
    - '127.0.0.1:5353'
  bootstrap_dns:
    - '9.9.9.9'
    - '1.1.1.1'
  enable_dnssec: true
  serve_http3: false
  ratelimit: 0
filters:
  - enabled: ${DNS_BLOCKLISTS_MIN}
    url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
    name: AdGuard Base Minimal
    id: 1
