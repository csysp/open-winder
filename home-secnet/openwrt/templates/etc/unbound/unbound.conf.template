server:
    username: "unbound"
    directory: "/var/lib/unbound"
    chroot: ""
    pidfile: "/var/run/unbound.pid"
    root-hints: "/etc/unbound/root.hints"
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    tls-cert-bundle: "/etc/ssl/certs/ca-certificates.crt"
    interface: 127.0.0.1@5353
    access-control: 127.0.0.0/8 allow
    hide-identity: yes
    hide-version: yes
    qname-minimisation: yes
    harden-dnssec-stripped: yes
    harden-referral-path: yes
    rrset-roundrobin: yes
    prefetch: yes
    cache-min-ttl: 120
    cache-max-ttl: 86400

forward-zone:
    name: "."
    forward-tls-upstream: yes
    forward-addr: 9.9.9.9@853#dns.quad9.net
    forward-addr: 1.1.1.1@853#cloudflare-dns.com

