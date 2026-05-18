#!/bin/bash
set -e

# ============================================================
# Nexus CLI Setup & Run Script for VPS (Ubuntu/Debian)
# Usage:
#   Dùng wallet (không cần node ID thủ công):
#     ./setup-nexus.sh --wallet 0x...
#
#   Dùng node ID có sẵn:
#     ./setup-nexus.sh --node-id abc123
#
#   Chạy có menu chọn:
#     ./setup-nexus.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ---------- CONFIG DEFAULT ----------
NODE_ID=""
WALLET_ADDR=""
MAX_DIFFICULTY="large"
HEADLESS=true
PM2_NAME="nexus-cli"

# ---------- PARSE ARGS ----------
while [[ $# -gt 0 ]]; do
    case $1 in
        --node-id)
            NODE_ID="$2"; shift 2 ;;
        --wallet)
            WALLET_ADDR="$2"; shift 2 ;;
        --difficulty|--max-difficulty)
            MAX_DIFFICULTY="$2"; shift 2 ;;
        --interactive)
            HEADLESS=false; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --wallet <ADDR>       Cung cấp ví, tự động tạo node (không cần node-id)"
            echo "  --node-id <ID>        Dùng node ID có sẵn từ app.nexus.xyz"
            echo "  --difficulty <LEVEL>  Độ khó (default: large)"
            echo "                        Options: small|small_medium|medium|large|extra_large|extra_large_2|extra_large_3|extra_large_4|extra_large_5"
            echo "  --interactive         Chạy interactive (hỏi từng bước)"
            echo "  -h, --help            Show this help"
            echo ""
            echo "Ví dụ:"
            echo "  ./setup-nexus.sh --wallet 0xAbC123..."
            echo "  ./setup-nexus.sh --node-id n1abc --difficulty extra_large_2"
            exit 0 ;;
        *)
            err "Unknown option: $1. Use --help for usage." ;;
    esac
done

# ---------- PRE-CHECKS ----------
log "Checking system..."

[[ "$(uname -s)" == "Linux" ]] || err "Script này chỉ cho Linux VPS."

for pkg in curl git; do
    command -v $pkg &>/dev/null || { log "Installing $pkg..."; sudo apt-get update -qq && sudo apt-get install -y -qq $pkg; }
done

# ---------- DETECT HARDWARE ----------
CPU_CORES=$(nproc)
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
log "Detected: ${CPU_CORES} cores, ${RAM_GB}GB RAM"

# Auto-suggest difficulty based on hardware
if [[ "$MAX_DIFFICULTY" == "large" ]]; then
    if [[ "$CPU_CORES" -ge 16 ]]; then
        MAX_DIFFICULTY="extra_large_2"
    elif [[ "$CPU_CORES" -ge 8 ]]; then
        MAX_DIFFICULTY="extra_large"
    elif [[ "$CPU_CORES" -ge 4 ]]; then
        MAX_DIFFICULTY="large"
    else
        MAX_DIFFICULTY="medium"
    fi
    log "Auto difficulty: $MAX_DIFFICULTY (based on ${CPU_CORES} cores)"
fi

# ---------- PROMPT IF NO ARGS ----------
if [[ -z "$NODE_ID" && -z "$WALLET_ADDR" ]]; then
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}   Nexus CLI - Chọn cách chạy${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo "1. Minh co wallet (tu dong tao node) - KHUYEN NGHI"
    echo "2. Minh co Node ID roi (lay tu app.nexus.xyz)"
    echo ""
    read -rp "Chon [1-2]: " CHOICE
    echo ""

    case $CHOICE in
        1)
            read -rp "Nhap wallet address: " WALLET_ADDR
            [[ -z "$WALLET_ADDR" ]] && err "Wallet address khong duoc de trong."
            ;;
        2)
            read -rp "Nhap node ID: " NODE_ID
            [[ -z "$NODE_ID" ]] && err "Node ID khong duoc de trong."
            ;;
        *)
            err "Lua chon khong hop le."
            ;;
    esac
fi

# ---------- INSTALL NEXUS CLI ----------
log "Cai dat Nexus CLI..."

if command -v nexus-cli &>/dev/null; then
    log "nexus-cli da co san: $(nexus-cli --version 2>/dev/null || echo 'ok')"
elif command -v nexus-network &>/dev/null; then
    log "nexus-network da co san"
else
    log "Dang tai tu https://cli.nexus.xyz/ ..."
    curl -sSf https://cli.nexus.xyz/ | sh
fi

# Detect the actual binary name
export PATH="$HOME/.cargo/bin:$HOME/.nexus:$PATH"

if command -v nexus-cli &>/dev/null; then
    NEXUS_BIN="nexus-cli"
elif command -v nexus-network &>/dev/null; then
    NEXUS_BIN="nexus-network"
elif [[ -f "$HOME/.cargo/bin/nexus-cli" ]]; then
    NEXUS_BIN="$HOME/.cargo/bin/nexus-cli"
elif [[ -f "$HOME/.cargo/bin/nexus-network" ]]; then
    NEXUS_BIN="$HOME/.cargo/bin/nexus-network"
else
    err "Khong tim thay nexus-cli/nexus-network binary. Kiem tra cai dat."
fi

log "Using binary: $NEXUS_BIN"

# ---------- REGISTER / CONFIGURE ----------
if [[ -n "$WALLET_ADDR" ]]; then
    log "Dang ky user voi wallet: $WALLET_ADDR"
    $NEXUS_BIN register-user --wallet-address "$WALLET_ADDR" || {
        warn "register-user failed, thu lai..."
        sleep 2
        $NEXUS_BIN register-user --wallet-address "$WALLET_ADDR"
    }

    log "Dang tao node tu dong..."
    $NEXUS_BIN register-node || {
        warn "register-node failed, thu lai..."
        sleep 2
        $NEXUS_BIN register-node
    }
    log "Dang ky thanh cong! Credentials luu tai ~/.nexus/credentials.json"

elif [[ -n "$NODE_ID" ]]; then
    mkdir -p "$HOME/.nexus"
    # Also try credentials.json format for newer versions
    echo "{\"node_id\": \"$NODE_ID\"}" > "$HOME/.nexus/config.json"
    echo "{\"node_id\": \"$NODE_ID\"}" > "$HOME/.nexus/credentials.json"
    log "Da luu node ID: $NODE_ID"
fi

# ---------- SETUP PM2 ----------
USE_PM2=false
if command -v pm2 &>/dev/null; then
    USE_PM2=true
else
    log "Cai dat Node.js & pm2..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - 2>/dev/null
    sudo apt-get install -y -qq nodejs 2>/dev/null
    npm install -g pm2 2>/dev/null && USE_PM2=true && log "pm2 installed." || warn "pm2 fail, se dung nohup."
fi

# ---------- START ----------
log "Khoi dong Nexus CLI (max-difficulty: $MAX_DIFFICULTY)..."

START_CMD="$NEXUS_BIN start"
if $HEADLESS; then
    START_CMD="$START_CMD --headless"
fi
START_CMD="$START_CMD --max-difficulty $MAX_DIFFICULTY"

if $USE_PM2; then
    pm2 delete "$PM2_NAME" 2>/dev/null || true
    pm2 start --name "$PM2_NAME" "$START_CMD"
    pm2 save
    pm2 startup 2>/dev/null && log "pm2 auto-start on reboot: OK" || true
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Nexus CLI da chay qua pm2!${NC}"
    echo -e "${GREEN}  pm2 logs nexus-cli   -> xem log${NC}"
    echo -e "${GREEN}  pm2 status           -> xem trang thai${NC}"
    echo -e "${GREEN}  pm2 stop nexus-cli   -> dung${NC}"
    echo -e "${GREEN}  https://app.nexus.xyz/compute -> check diem${NC}"
    echo -e "${GREEN}============================================${NC}"
else
    nohup $START_CMD > "$HOME/.nexus/nexus-cli.log" 2>&1 &
    PID=$!
    echo $PID > "$HOME/.nexus/nexus-cli.pid"
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Nexus CLI PID: $PID${NC}"
    echo -e "${GREEN}  Log: ~/.nexus/nexus-cli.log${NC}"
    echo -e "${GREEN}  Stop: kill $PID${NC}"
    echo -e "${GREEN}  https://app.nexus.xyz/compute -> check diem${NC}"
    echo -e "${GREEN}============================================${NC}"
fi
