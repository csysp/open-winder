#![forbid(unsafe_code)]

use anyhow::{anyhow, Context, Result};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use clap::Parser;
use hmac::{Hmac, Mac};
use pqcrypto_mlkem::mlkem768 as kem;
use pqcrypto_traits::kem::{Ciphertext as CtTrait, PublicKey as PkTrait, SharedSecret as SsTrait};
use sha2::Sha256;
use std::fs;
use std::net::{SocketAddr, ToSocketAddrs, UdpSocket};
use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, serde::Deserialize)]
struct Config {
    router_host: String,
    spa_port: u16,
    wg_port: u16,
    kem_pub_b64: String,
    psk_b64: String,
}

#[derive(Parser, Debug)]
#[command(name = "spa-pq-client", version)]
struct Cli {
    /// Path to client config JSON
    #[arg(long, default_value = "clients/spa-pq-client.json")]
    config: PathBuf,
}

fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::from_secs(0))
        .as_secs() as i64
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let cfg_data = fs::read_to_string(&cli.config)
        .with_context(|| format!("read {}", cli.config.display()))?;
    let cfg: Config = serde_json::from_str(&cfg_data)?;

    let pub_bytes = STANDARD.decode(cfg.kem_pub_b64.trim())?;
    let psk = STANDARD.decode(cfg.psk_b64.trim())?;
    if psk.len() != 32 {
        return Err(anyhow!("psk must be 32 bytes"));
    }
    let pk =
        <kem::PublicKey as PkTrait>::from_bytes(&pub_bytes).map_err(|_| anyhow!("bad pubkey"))?;

    let addr = format!("{}:{}", cfg.router_host, cfg.spa_port);
    let mut addrs = addr.to_socket_addrs()?;
    let dst = addrs.next().ok_or_else(|| anyhow!("resolve {}", addr))?;

    let sock = UdpSocket::bind("0.0.0.0:0")?;
    sock.connect(dst)?;
    // derive local IPv4
    let local = sock.local_addr()?;
    let local_v4 = match local {
        SocketAddr::V4(v4) => v4,
        _ => return Err(anyhow!("local address not IPv4")),
    };
    let client_ip_u32 = u32::from_be_bytes(local_v4.ip().octets());

    // build fields
    let mut nonce = [0u8; 16];
    getrandom::getrandom(&mut nonce).map_err(|e| anyhow!(e))?;
    let ts = now_unix();

    // encapsulate
    let (ct, shared) = kem::encapsulate(&pk);
    // Types: ct: kem::Ciphertext, shared: kem::SharedSecret
    let ct_bytes = <kem::Ciphertext as CtTrait>::as_bytes(&ct);
    let key = <kem::SharedSecret as SsTrait>::as_bytes(&shared);

    // HMAC over PSK || nonce || client_ip || ts
    let mut msg = Vec::with_capacity(32 + 16 + 4 + 8);
    msg.extend_from_slice(&psk);
    msg.extend_from_slice(&nonce);
    msg.extend_from_slice(&client_ip_u32.to_be_bytes());
    msg.extend_from_slice(&ts.to_be_bytes());
    let mut mac = HmacSha256::new_from_slice(key).map_err(|_| anyhow!("hmac key"))?;
    mac.update(&msg);
    let tag = mac.finalize().into_bytes();

    // packet v1: u8 ver(1) | u16 ct_len | ct | nonce(16) | ts(i64) | client_ip(u32) | tag(32)
    let ct_len = ct_bytes.len();
    if ct_len > u16::MAX as usize {
        return Err(anyhow!("ct too large"));
    }
    let mut pkt = Vec::with_capacity(1 + 2 + ct_len + 16 + 8 + 4 + 32);
    pkt.push(1u8);
    pkt.extend_from_slice(&(ct_len as u16).to_be_bytes());
    pkt.extend_from_slice(ct_bytes);
    pkt.extend_from_slice(&nonce);
    pkt.extend_from_slice(&ts.to_be_bytes());
    pkt.extend_from_slice(&client_ip_u32.to_be_bytes());
    pkt.extend_from_slice(&tag);

    sock.send(&pkt)?;
    sock.set_read_timeout(Some(Duration::from_millis(1000)))?;
    let mut buf = [0u8; 16];
    match sock.recv(&mut buf) {
        Ok(n) if n >= 2 && &buf[..2] == b"OK" => {
            println!("OK, port open for {} seconds.", 45);
        }
        _ => {
            println!("Knock sent. If valid, port should open shortly.");
        }
    }
    Ok(())
}
