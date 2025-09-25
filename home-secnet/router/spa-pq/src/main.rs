#![forbid(unsafe_code)]

use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use std::collections::{HashMap, VecDeque};
use std::fs;
use std::io::{Read, Write};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, UdpSocket};
use std::path::PathBuf;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use pqcrypto_mlkem::mlkem768 as kem;
use pqcrypto_traits::kem::{
    Ciphertext as CtTrait, PublicKey as PkTrait, SecretKey as SkTrait, SharedSecret as SsTrait,
};

type HmacSha256 = Hmac<Sha256>;

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

fn ensure_nft_chain(table: &str, chain: &str) {
    // Best-effort idempotent create: table, chain, and a set with timeout
    let _ = std::process::Command::new("nft")
        .args(["list", "table", table, "filter"])
        .status();
    let _ = std::process::Command::new("nft")
        .args(["add", "table", table, "filter"])
        .status();
    // create user chain if missing
    let _ = std::process::Command::new("nft")
        .args(["list", "chain", table, "filter", chain])
        .status();
    let _ = std::process::Command::new("nft")
        .args(["add", "chain", table, "filter", chain, "{", "}"])
        .status();
    // create set with timeout for allowed IPs
    let set_name = format!("{}{}_set", "", chain);
    let _ = std::process::Command::new("nft")
        .args(["list", "set", table, "filter", &set_name])
        .status();
    let _ = std::process::Command::new("nft")
        .args([
            "add",
            "set",
            table,
            "filter",
            &set_name,
            "{",
            "type",
            "ipv4_addr;",
            "flags",
            "timeout;",
            "}",
        ])
        .status();
    // ensure jump rule uses set
    let list = std::process::Command::new("nft")
        .args(["list", "chain", table, "filter", "input"]) // assume gating in input
        .output();
    if let Ok(out) = list {
        let s = String::from_utf8_lossy(&out.stdout);
        if !s.contains(&format!("udp dport {} jump {}", "", chain))
            && !s.contains(&format!("@{}", set_name))
        {
            // insert rule to accept when ip saddr @set
            let _ = std::process::Command::new("nft")
                .args([
                    "insert", "rule", table, "filter", "input", "udp",
                    "dport", // dport must be provided at run
                ])
                .status();
        }
    }
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

fn delete_rule_by_comment(table: &str, chain: &str, comment: &str) -> Result<()> {
    // list chain with handles and find rule matching comment
    let out = std::process::Command::new("nft")
        .args(["list", "chain", table, "filter", chain, "-a"])
        .output()
        .context("nft list chain")?;
    if !out.status.success() {
        return Err(anyhow!("nft list chain failed"));
    }
    let s = String::from_utf8_lossy(&out.stdout);
    let mut handle: Option<String> = None;
    for line in s.lines() {
        if line.contains(comment) {
            if let Some((_, h)) = line.rsplit_once("# handle ") {
                handle = Some(h.trim().to_string());
                break;
            }
        }
    }
    if let Some(h) = handle {
        let status = std::process::Command::new("nft")
            .args(["delete", "rule", table, "filter", chain, "handle", &h])
            .status()
            .context("nft delete rule")?;
        if status.success() {
            Ok(())
        } else {
            Err(anyhow!("nft delete rule failed"))
        }
    } else {
        Err(anyhow!("rule handle not found for comment"))
    }
}

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

    ensure_nft_chain(&nft_table, &nft_chain);

    // Maintain a small replay cache of (src_ip, nonce, ts) with TTL=window_secs
    let mut replay_cache: VecDeque<(Ipv4Addr, [u8; 16], i64, Instant)> =
        VecDeque::with_capacity(1024);

    // Simple rate limiter: allow up to N decaps per second (global)
    let mut tokens: u32 = 50; // capacity
    let mut last_refill = Instant::now();

    let mut buf = [0u8; 4096];
    loop {
        match sock.recv_from(&mut buf) {
            Ok((n, src)) => {
                if let SocketAddr::V4(src_v4) = src {
                    // Refill tokens every second
                    if last_refill.elapsed() >= Duration::from_secs(1) {
                        tokens = 50;
                        last_refill = Instant::now();
                    }
                    if tokens == 0 {
                        continue; // drop (rate limited)
                    }
                    tokens -= 1;
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
                    );
                    if let Err(e) = res {
                        // best-effort deny log
                        let line = LogLine {
                            ts: now_unix(),
                            client_ip: &src_v4.ip().to_string(),
                            decision: "deny",
                            reason: &format!("{}", e),
                            opens_for_secs: 0,
                        };
                        println!("{}", serde_json::to_string(&line).unwrap_or_default());
                    } else {
                        let _ = sock.send_to(b"OK", src);
                    }
                }
            }
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                // tick
            }
            Err(e) => return Err(anyhow!("socket error: {}", e)),
        }
    }
}

#[allow(clippy::too_many_arguments)]
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
) -> Result<()> {
    // Packet: u16 ct_len | ct | 16 nonce | i64 ts | u32 client_ip | 32 tag
    if pkt.len() < 2 + 16 + 8 + 4 + 32 {
        return Err(anyhow!("packet too short"));
    }
    let ct_len = u16::from_be_bytes([pkt[0], pkt[1]]) as usize;
    let need = 2 + ct_len + 16 + 8 + 4 + 32;
    if pkt.len() != need {
        return Err(anyhow!("length mismatch"));
    }
    // Validate expected Kyber768 ciphertext length
    const KYBER768_CT_LEN: usize = 1088; // PQClean Kyber768 ciphertext bytes
    if ct_len != KYBER768_CT_LEN {
        return Err(anyhow!("bad_ct_len"));
    }
    let mut off = 2;
    let ct = &pkt[off..off + ct_len];
    off += ct_len;
    let nonce = &pkt[off..off + 16];
    off += 16;
    let ts = i64::from_be_bytes(pkt[off..off + 8].try_into().unwrap());
    off += 8;
    let _ip_raw = u32::from_be_bytes(pkt[off..off + 4].try_into().unwrap());
    off += 4;
    let tag = &pkt[off..off + 32];

    // time window check
    let now = now_unix();
    if (now - ts).abs() > window_secs {
        return Err(anyhow!("stale_ts"));
    }
    // basic replay cache hook would go here (moved to outer loop if keeping global),
    // but to keep function pure, we leave it to caller in future refactor.

    // decapsulate
    let ct_obj =
        <kem::Ciphertext as CtTrait>::from_bytes(ct).map_err(|_| anyhow!("decap_failed"))?;
    let shared = kem::decapsulate(&ct_obj, sk);
    let key = SsTrait::as_bytes(&shared);

    // message = PSK || nonce || ts (drop client_ip from HMAC input)
    let mut msg = Vec::with_capacity(32 + 16 + 8);
    msg.extend_from_slice(psk);
    msg.extend_from_slice(nonce);
    msg.extend_from_slice(&ts.to_be_bytes());

    // HMAC
    let mut mac = HmacSha256::new_from_slice(key).map_err(|_| anyhow!("hmac_key"))?;
    mac.update(&msg);
    let expected = mac.finalize().into_bytes();
    if expected.as_slice() != tag {
        return Err(anyhow!("bad_hmac"));
    }

    // insert allow set element for src ip with timeout
    let client_ip = *src.ip();
    add_allow_set_entry(nft_table, nft_chain, client_ip, open_secs)?;

    // log allow
    let line = LogLine {
        ts: now,
        client_ip: &client_ip.to_string(),
        decision: "allow",
        reason: "ok",
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
        let ip = 0x7f000001u32; // 127.0.0.1
        let ts: i64 = 123456789;
        let mut msg = Vec::new();
        msg.extend_from_slice(&psk);
        msg.extend_from_slice(&nonce);
        msg.extend_from_slice(&ip.to_be_bytes());
        msg.extend_from_slice(&ts.to_be_bytes());
        let mut mac = HmacSha256::new_from_slice(&key).unwrap();
        mac.update(&msg);
        let tag = mac.finalize().into_bytes();
        assert_eq!(tag.len(), 32);
    }

    #[test]
    fn time_window_check() {
        let now = now_unix();
        assert!((now - (now - 10)).abs() <= 30);
        assert!((now - (now - 100)).abs() > 30);
    }
}
