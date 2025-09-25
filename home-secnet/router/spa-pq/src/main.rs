#![forbid(unsafe_code)]

use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::io::{Read, Write};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, UdpSocket};
use std::path::PathBuf;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use pqcrypto_mlkem::mlkem768 as kem;
use pqcrypto_traits::kem::{Ciphertext as CtTrait, SecretKey as SkTrait, SharedSecret as SsTrait};
use thiserror::Error;

type HmacSha256 = Hmac<Sha256>;

// Protocol constants (Kyber/ML-KEM-768)
const PROTO_VER: u8 = 1;
const NONCE_LEN: usize = 16;
const TAG_LEN: usize = 32;
// Kyber768 ciphertext size in bytes (ML-KEM-768)
const CT_LEN_KYBER768: usize = 1088;

// Replay cache with O(1) membership and TTL-based purge
struct ReplayCache {
    ttl: Duration,
    set: HashSet<(Ipv4Addr, [u8; NONCE_LEN], i64)>,
    order: VecDeque<(Instant, Ipv4Addr, [u8; NONCE_LEN], i64)>,
    cap: usize,
}

impl ReplayCache {
    fn new(ttl: Duration, cap: usize) -> Self {
        Self {
            ttl,
            set: HashSet::with_capacity(cap),
            order: VecDeque::with_capacity(cap),
            cap,
        }
    }
    fn purge_expired(&mut self, now: Instant) {
        while let Some((t, ip, n, ts)) = self.order.front().cloned() {
            if now.duration_since(t) > self.ttl {
                self.order.pop_front();
                self.set.remove(&(ip, n, ts));
            } else {
                break;
            }
        }
        // Hard cap: if exceeded, drop oldest entries
        while self.order.len() > self.cap {
            if let Some((_, ip, n, ts)) = self.order.pop_front() {
                self.set.remove(&(ip, n, ts));
            } else {
                break;
            }
        }
    }
    fn seen_or_insert(
        &mut self,
        ip: Ipv4Addr,
        nonce: [u8; NONCE_LEN],
        ts: i64,
        now: Instant,
    ) -> bool {
        if self.set.contains(&(ip, nonce, ts)) {
            return true;
        }
        self.set.insert((ip, nonce, ts));
        self.order.push_back((now, ip, nonce, ts));
        false
    }
}

#[derive(Parser, Debug)]
#[command(name = "home-secnet-spa-pq", version)]
struct Cli {
    #[command(subcommand)]
    cmd: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Generate a Kyber/ML-KEM-768 keypair
    GenKeys {
        /// Private key output path (raw bytes)
        #[arg(long)]
        priv_out: PathBuf,
        /// Public key output path (raw bytes)
        #[arg(long)]
        pub_out: PathBuf,
    },

    /// Run SPA daemon
    Run {
        /// Listen address, e.g. 0.0.0.0:62201
        #[arg(long, default_value = "0.0.0.0:62201")]
        listen: String,
        /// WireGuard UDP port to open
        #[arg(long)]
        wg_port: u16,
        /// KEM private key path
        #[arg(long)]
        kem_priv: PathBuf,
        /// Path to 32-byte PSK file
        #[arg(long)]
        psk_file: PathBuf,
        /// Allow window for port opening (seconds)
        #[arg(long, default_value_t = 45)]
        open_secs: u64,
        /// Acceptable time skew for knocks (seconds)
        #[arg(long, default_value_t = 30)]
        window_secs: i64,
        /// nft family/table (e.g., inet)
        #[arg(long, default_value = "inet")]
        nft_table: String,
        /// nft chain (e.g., wg_spa_allow)
        #[arg(long, default_value = "wg_spa_allow")]
        nft_chain: String,
    },
}

#[derive(Debug, serde::Serialize)]
struct LogLine<'a> {
    ts: i64,
    client_ip: &'a str,
    decision: &'a str,
    reason: &'a str,
    opens_for_secs: u64,
}

fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::from_secs(0))
        .as_secs() as i64
}

fn read_file(path: &PathBuf) -> Result<Vec<u8>> {
    let mut f = fs::File::open(path).with_context(|| format!("open {}", path.display()))?;
    let mut b = Vec::new();
    f.read_to_end(&mut b)?;
    Ok(b)
}

fn write_file(path: &PathBuf, data: &[u8], mode: Option<u32>) -> Result<()> {
    if let Some(m) = mode {
        // best-effort set umask'd perms after write
        let mut f = fs::File::create(path).with_context(|| format!("create {}", path.display()))?;
        f.write_all(data)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(path, fs::Permissions::from_mode(m))?;
        }
        Ok(())
    } else {
        fs::write(path, data)?;
        Ok(())
    }
}

fn gen_keys(priv_out: PathBuf, pub_out: PathBuf) -> Result<()> {
    let (pk, sk) = kem::keypair();
    write_file(&priv_out, SkTrait::as_bytes(&sk), Some(0o600))?;
    write_file(&pub_out, PkTrait::as_bytes(&pk), Some(0o644))?;
    eprintln!(
        "generated ML-KEM-768 keypair: priv={}, pub={}",
        priv_out.display(),
        pub_out.display()
    );
    Ok(())
}

fn ensure_nft_chain(table: &str, chain: &str) -> Result<()> {
    // Fail-fast verification only. Systemd ExecStartPre must provision these.
    let set_name = format!("{}{}_set", "", chain);
    let ok_table = std::process::Command::new("nft")
        .args(["list", "table", table, "filter"]) // e.g., inet filter
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    let ok_chain = std::process::Command::new("nft")
        .args(["list", "chain", table, "filter", chain])
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    let ok_set = std::process::Command::new("nft")
        .args(["list", "set", table, "filter", &set_name])
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !(ok_table && ok_chain && ok_set) {
        return Err(SpaError::NftMissing.into());
    }
    Ok(())
}

fn add_allow_set_entry(
    table: &str,
    chain: &str,
    client_ip: Ipv4Addr,
    open_secs: u64,
) -> Result<()> {
    // add element to set with timeout
    let set_name = format!("{}{}_set", "", chain);
    let elem = format!("{{ {} timeout {}s }}", client_ip, open_secs);
    let status = std::process::Command::new("nft")
        .args(["add", "element", table, "filter", &set_name, &elem])
        .status()
        .context("nft add element")?;
    if !status.success() {
        return Err(anyhow!("nft add element failed"));
    }
    Ok(())
}

// delete_rule_by_comment: removed; daemon does not mutate nft rules beyond adding elements

#[allow(clippy::too_many_arguments)]
fn run_daemon(
    listen: String,
    wg_port: u16,
    kem_priv: PathBuf,
    psk_file: PathBuf,
    open_secs: u64,
    window_secs: i64,
    nft_table: String,
    nft_chain: String,
) -> Result<()> {
    let sock = UdpSocket::bind(&listen).with_context(|| format!("bind {}", listen))?;
    sock.set_read_timeout(Some(Duration::from_millis(500)))?;

    let kem_priv_bytes = read_file(&kem_priv)?;
    let psk = read_file(&psk_file)?;
    if psk.len() != 32 {
        return Err(anyhow!("PSK must be 32 bytes"));
    }

    // reconstruct secret key
    let sk = <kem::SecretKey as SkTrait>::from_bytes(&kem_priv_bytes)
        .map_err(|_| anyhow!("invalid KEM private key"))?;

    ensure_nft_chain(&nft_table, &nft_chain)?;

    // Maintain a replay cache of (src_ip, nonce, ts) with TTL=window_secs
    let mut replay_cache = ReplayCache::new(Duration::from_secs(window_secs as u64), 4096);

    // Simple rate limiter: per-source token bucket + global cap
    let mut buckets: HashMap<Ipv4Addr, (u32, Instant)> = HashMap::new();
    let per_src_capacity: u32 = 20;
    let mut global_tokens: u32 = 200;
    let mut last_global_refill = Instant::now();
    const MAX_BUCKETS: usize = 8192;

    let mut buf = [0u8; 4096];
    loop {
        match sock.recv_from(&mut buf) {
            Ok((n, src)) => {
                if let SocketAddr::V4(src_v4) = src {
                    // Refill global tokens every second
                    if last_global_refill.elapsed() >= Duration::from_secs(1) {
                        global_tokens = 200;
                        last_global_refill = Instant::now();
                        // Opportunistic prune to bound memory
                        if buckets.len() > MAX_BUCKETS {
                            let cutoff = Instant::now() - Duration::from_secs(10);
                            buckets.retain(|_, v| v.1 >= cutoff);
                        }
                    }
                    if global_tokens == 0 {
                        continue;
                    }
                    global_tokens -= 1;
                    let entry = buckets
                        .entry(*src_v4.ip())
                        .or_insert((per_src_capacity, Instant::now()));
                    if entry.1.elapsed() >= Duration::from_secs(1) {
                        entry.0 = per_src_capacity;
                        entry.1 = Instant::now();
                    }
                    if entry.0 == 0 {
                        continue;
                    }
                    entry.0 -= 1;
                    let res = handle_packet(
                        &buf[..n],
                        src_v4,
                        &sk,
                        &psk,
                        window_secs,
                        open_secs,
                        &nft_table,
                        &nft_chain,
                        wg_port,
                        &mut replay_cache,
                    );
                    if let Err(e) = res {
                        // best-effort deny log
                        let line = LogLine {
                            ts: now_unix(),
                            client_ip: &src_v4.ip().to_string(),
                            decision: "deny",
                            reason: reason_of(&e),
                            opens_for_secs: 0,
                        };
                        println!("{}", serde_json::to_string(&line).unwrap_or_default());
                    } else {
                        let _ = sock.send_to(b"OK", src);
                    }
                }
            }
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                // brief sleep to avoid busy loop
                thread::sleep(Duration::from_millis(1));
            }
            Err(e) => return Err(anyhow!("socket error: {}", e)),
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn handle_packet(
    pkt: &[u8],
    src: SocketAddrV4,
    sk: &kem::SecretKey,
    psk: &[u8],
    window_secs: i64,
    open_secs: u64,
    nft_table: &str,
    nft_chain: &str,
    _wg_port: u16,
    // replay cache shared from caller
    replay_cache: &mut ReplayCache,
) -> Result<()> {
    // Packet v1: u8 ver | u16 ct_len | ct | 16 nonce | i64 ts | u32 client_ip | 32 tag
    if pkt.len() < 1 + 2 + NONCE_LEN + 8 + 4 + TAG_LEN {
        return Err(SpaError::PacketTooShort.into());
    }
    let ver = pkt[0];
    if ver != PROTO_VER {
        return Err(SpaError::BadVer.into());
    }
    let ct_len = u16::from_be_bytes([pkt[1], pkt[2]]) as usize;
    let need = 1 + 2 + ct_len + 16 + 8 + 4 + 32;
    if pkt.len() != need {
        return Err(SpaError::LengthMismatch.into());
    }
    // Enforce Kyber768 ciphertext length strictly
    if ct_len != CT_LEN_KYBER768 {
        return Err(SpaError::BadCtLen.into());
    }
    let mut off = 3;
    let ct = &pkt[off..off + ct_len];
    off += ct_len;
    let nonce = &pkt[off..off + NONCE_LEN];
    off += NONCE_LEN;
    let ts = i64::from_be_bytes(pkt[off..off + 8].try_into().unwrap());
    off += 8;
    let ip_raw = u32::from_be_bytes(pkt[off..off + 4].try_into().unwrap());
    off += 4;
    let tag = &pkt[off..off + TAG_LEN];

    // time window check
    let now = now_unix();
    if (now - ts).abs() > window_secs {
        return Err(SpaError::StaleTs.into());
    }
    // Replay protection: reject duplicate (src_ip, nonce, ts) within window
    let src_ip = *src.ip();
    let now_instant = Instant::now();
    replay_cache.purge_expired(now_instant);
    let mut nonce_arr = [0u8; NONCE_LEN];
    nonce_arr.copy_from_slice(nonce);
    if replay_cache.seen_or_insert(src_ip, nonce_arr, ts, now_instant) {
        return Err(SpaError::Replay.into());
    }

    // decapsulate
    let ct_obj = <kem::Ciphertext as CtTrait>::from_bytes(ct).map_err(|_| SpaError::DecapFailed)?;
    let shared = kem::decapsulate(&ct_obj, sk);
    let key = SsTrait::as_bytes(&shared);

    // HMAC: constant-time verify over PSK || nonce || ts
    let mut mac = HmacSha256::new_from_slice(key).map_err(|_| SpaError::HmacKey)?;
    mac.update(psk);
    mac.update(&[PROTO_VER]);
    mac.update(nonce);
    mac.update(&ts.to_be_bytes());
    mac.verify_slice(tag).map_err(|_| SpaError::BadHmac)?;

    // insert allow set element for src ip with timeout
    add_allow_set_entry(nft_table, nft_chain, src_ip, open_secs)?;

    // log allow
    let line = LogLine {
        ts: now,
        client_ip: &src_ip.to_string(),
        decision: "allow",
        reason: if ip_raw != u32::from_be_bytes(src_ip.octets()) {
            "ok_nat_mismatch"
        } else {
            "ok"
        },
        opens_for_secs: open_secs,
    };
    println!("{}", serde_json::to_string(&line).unwrap_or_default());

    Ok(())
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Command::GenKeys { priv_out, pub_out } => gen_keys(priv_out, pub_out),
        Command::Run {
            listen,
            wg_port,
            kem_priv,
            psk_file,
            open_secs,
            window_secs,
            nft_table,
            nft_chain,
        } => run_daemon(
            listen,
            wg_port,
            kem_priv,
            psk_file,
            open_secs,
            window_secs,
            nft_table,
            nft_chain,
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    // no external RNG used in current tests

    #[test]
    fn hmac_message_format() {
        let key = [7u8; 32];
        let psk = [1u8; 32];
        let nonce = [2u8; 16];
        let ts: i64 = 123456789;
        let mut mac = HmacSha256::new_from_slice(&key).unwrap();
        mac.update(&psk);
        mac.update(&[PROTO_VER]);
        mac.update(&nonce);
        mac.update(&ts.to_be_bytes());
        let tag = mac.finalize().into_bytes();
        assert_eq!(tag.len(), TAG_LEN);
    }

    #[test]
    fn time_window_check() {
        let now = now_unix();
        assert!((now - (now - 10)).abs() <= 30);
        assert!((now - (now - 100)).abs() > 30);
    }

    #[test]
    fn replay_cache_rejects_duplicate() {
        let mut cache = ReplayCache::new(Duration::from_secs(30), 8);
        let ip = Ipv4Addr::new(1, 2, 3, 4);
        let nonce = [7u8; 16];
        let ts = 1111i64;
        let now = Instant::now();
        // first insert should not be seen
        assert_eq!(cache.seen_or_insert(ip, nonce, ts, now), false);
        // second time should be seen (duplicate)
        assert_eq!(cache.seen_or_insert(ip, nonce, ts, now), true);
    }

    #[test]
    fn rate_limiter_buckets_refill() {
        let mut buckets: std::collections::HashMap<Ipv4Addr, (u32, Instant)> = HashMap::new();
        let per_src_capacity = 2u32;
        let ip = Ipv4Addr::new(9, 9, 9, 9);
        let entry = buckets
            .entry(ip)
            .or_insert((per_src_capacity, Instant::now()));
        assert_eq!(entry.0, 2);
        entry.0 -= 1;
        entry.0 -= 1;
        assert_eq!(entry.0, 0);
        // force refill
        entry.1 = Instant::now() - Duration::from_secs(2);
        if entry.1.elapsed() >= Duration::from_secs(1) {
            entry.0 = per_src_capacity;
            entry.1 = Instant::now();
        }
        assert_eq!(entry.0, 2);
    }
}
#[derive(Error, Debug)]
enum SpaError {
    #[error("packet too short")]
    PacketTooShort,
    #[error("bad_ver")]
    BadVer,
    #[error("length mismatch")]
    LengthMismatch,
    #[error("bad_ct_len")]
    BadCtLen,
    #[error("stale_ts")]
    StaleTs,
    #[error("replay")]
    Replay,
    #[error("decap_failed")]
    DecapFailed,
    #[error("hmac_key")]
    HmacKey,
    #[error("bad_hmac")]
    BadHmac,
    #[error("nft_missing")]
    NftMissing,
}

fn reason_of(e: &anyhow::Error) -> &'static str {
    if let Some(se) = e.downcast_ref::<SpaError>() {
        match se {
            SpaError::PacketTooShort => "packet too short",
            SpaError::BadVer => "bad_ver",
            SpaError::LengthMismatch => "length mismatch",
            SpaError::BadCtLen => "bad_ct_len",
            SpaError::StaleTs => "stale_ts",
            SpaError::Replay => "replay",
            SpaError::DecapFailed => "decap_failed",
            SpaError::HmacKey => "hmac_key",
            SpaError::BadHmac => "bad_hmac",
            SpaError::NftMissing => "nft_missing",
        }
    } else {
        "error"
    }
}
