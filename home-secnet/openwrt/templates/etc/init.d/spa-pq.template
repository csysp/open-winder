#!/bin/sh /etc/rc.common
# open-winder SPA PQ procd service
START=95
USE_PROCD=1

NAME="spa-pq"
BIN="/usr/bin/${SPA_PQ_BIN:-home-secnet-spa-pq}"
RUN_USER="root"
RUN_GROUP="root"
CONFIG_DIR="/etc/spa"
LOG_OPTS=""

start_service() {
    [ -x "$BIN" ] || return 1
    procd_open_instance
    procd_set_param command "$BIN" \
        --listen 0.0.0.0:${SPA_PQ_PORT} \
        --nft-table inet \
        --nft-chain wg_spa_allow \
        --open-secs ${SPA_PQ_OPEN_SECS} \
        --window-secs ${SPA_PQ_WINDOW_SECS} \
        --kem ${SPA_PQ_KEM:-kyber768} \
        --psk-file ${SPA_PQ_PSK_FILE:-/etc/spa/psk.bin} \
        --keys-dir ${CONFIG_DIR}
    procd_set_param respawn 2000 5 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    :
}

