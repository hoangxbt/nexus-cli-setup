#!/bin/bash
set -e

# ============================================================
# Nexus CLI - 1 lenh cai + chay tren VPS
#   curl -sSf https://raw.githubusercontent.com/hoangxbt/nexus-cli-setup/master/setup-nexus.sh | bash -s -- WALLET_ADDRESS
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }

WALLET="${1:-}"
[[ -z "$WALLET" ]] && err "Usage: bash setup-nexus.sh 0xWALLET_ADDRESS"
[[ "$(uname -s)" != "Linux" ]] && err "Script chi cho Linux VPS."

# ---------- CAI DAT PHU THUOC ----------
log "Cai dat packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq curl git build-essential pkg-config libssl-dev protobuf-compiler 2>/dev/null

# ---------- CAI DAT NEXUS CLI ----------
log "Cai dat Nexus CLI..."
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.nexus:$PATH"

if ! command -v nexus-cli &>/dev/null && ! command -v nexus-network &>/dev/null; then
    log "Chay trinh cai dat chinh thuc..."
    curl -sSf https://cli.nexus.xyz/ | sh

    # Reload env after install
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.nexus:$PATH"
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
fi

# ---------- TIM BINARY ----------
NEXUS_BIN=""
for bin in nexus-cli nexus-network; do
    if command -v "$bin" &>/dev/null; then
        NEXUS_BIN="$bin"; break
    fi
done

# Tim bang find neu chua co trong PATH
if [[ -z "$NEXUS_BIN" ]]; then
    FOUND=$(find "$HOME/.cargo" "$HOME/.nexus" "$HOME/.local" /usr/local/bin -maxdepth 3 -name "nexus-cli" -o -name "nexus-network" 2>/dev/null | head -1)
    if [[ -n "$FOUND" ]]; then
        NEXUS_BIN="$FOUND"
    fi
fi

[[ -z "$NEXUS_BIN" ]] && {
    warn "Khong tim thay binary. Cac file trong ~/.cargo/bin/:"
    ls -la "$HOME/.cargo/bin/" 2>/dev/null || echo "  -> ~/.cargo/bin/ khong ton tai"
    warn "Thu cai lai thu cong: curl https://cli.nexus.xyz/ | sh"
    err "Sau do chay: source ~/.bashrc && nexus-cli register-user --wallet-address $WALLET"
}

log "Binary: $NEXUS_BIN ($($NEXUS_BIN --version 2>/dev/null || echo 'ok'))"

# ---------- DANG KY USER & TAO NODE ----------
log "Dang ky user: $WALLET"
$NEXUS_BIN register-user --wallet-address "$WALLET" || {
    warn "Retry register-user..."
    sleep 3
    $NEXUS_BIN register-user --wallet-address "$WALLET" || err "register-user that bai."
}

log "Tao node tu dong..."
$NEXUS_BIN register-node || {
    warn "Retry register-node..."
    sleep 3
    $NEXUS_BIN register-node || err "register-node that bai."
}
log "Dang ky OK. Credentials: ~/.nexus/credentials.json"

# ---------- DETECT HARDWARE & DIFFICULTY ----------
CPU_CORES=$(nproc)
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
log "Hardware: ${CPU_CORES} cores, ${RAM_GB}GB RAM"

if   [[ "$CPU_CORES" -ge 16 ]]; then DIFF="extra_large_2"
elif [[ "$CPU_CORES" -ge 8 ]];  then DIFF="extra_large"
elif [[ "$CPU_CORES" -ge 4 ]];  then DIFF="large"
else DIFF="medium"; fi
log "Difficulty: $DIFF"

# ---------- CAI PM2 ----------
if ! command -v pm2 &>/dev/null; then
    log "Cai dat pm2..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - 2>/dev/null
    sudo apt-get install -y -qq nodejs 2>/dev/null
    npm install -g pm2 2>/dev/null || warn "pm2 cai that bai, dung nohup."
fi

# ---------- START ----------
log "Khoi dong $NEXUS_BIN --headless --max-difficulty $DIFF"

if command -v pm2 &>/dev/null; then
    pm2 delete nexus 2>/dev/null || true
    pm2 start "$NEXUS_BIN" --name nexus -- start --headless --max-difficulty "$DIFF"
    pm2 save
    pm2 startup 2>/dev/null && log "pm2 auto-start: OK" || true
    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN} Nexus CLI da chay!${NC}"
    echo -e "${GREEN} pm2 logs nexus      -> xem log${NC}"
    echo -e "${GREEN} pm2 status          -> trang thai${NC}"
    echo -e "${GREEN} pm2 stop nexus      -> dung${NC}"
    echo -e "${GREEN} https://app.nexus.xyz/compute${NC}"
    echo -e "${GREEN}=====================================${NC}"
else
    mkdir -p "$HOME/.nexus"
    nohup "$NEXUS_BIN" start --headless --max-difficulty "$DIFF" > "$HOME/.nexus/nexus-cli.log" 2>&1 &
    PID=$!
    echo "$PID" > "$HOME/.nexus/nexus-cli.pid"
    echo -e "${GREEN}Nexus CLI PID: $PID | Log: ~/.nexus/nexus-cli.log | Stop: kill $PID${NC}"
fi
