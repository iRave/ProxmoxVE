#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: [Contributor]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/zeroclaw-labs/zeroclaw

# ============================================================================
# ZeroClaw Installation Script
# ============================================================================
# Installs ZeroClaw AI assistant infrastructure in an LXC container
# Pre-built binary installation from GitHub releases
# ============================================================================

set -e

# Color output (simple, no external deps)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

msg_info() { echo -e "${CYAN}  ℹ️  $1${NC}"; }
msg_ok() { echo -e "${GREEN}  ✔️  $1${NC}"; }
msg_error() { echo -e "${RED}  ❌  $1${NC}"; }

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

detect_architecture() {
  local arch=$(uname -m)
  case $arch in
    x86_64) echo "x86_64-unknown-linux-gnu" ;;
    aarch64) echo "aarch64-unknown-linux-gnu" ;;
    armv7l) echo "armv7-unknown-linux-gnueabihf" ;;
    *)
      msg_error "Unsupported architecture: $arch"
      exit 1
      ;;
  esac
}

get_latest_release() {
  curl -fsSL https://api.github.com/repos/zeroclaw-labs/zeroclaw/releases/latest 2>/dev/null | \
    grep '"tag_name"' | cut -d'"' -f4
}

# ============================================================================
# MAIN INSTALLATION
# ============================================================================

echo ""
echo "  🚀 Installing ZeroClaw..."
echo ""

# Step 1: Install dependencies
msg_info "Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl git ca-certificates > /dev/null 2>&1
msg_ok "Installed dependencies"

# Step 2: Download ZeroClaw binary
msg_info "Downloading ZeroClaw..."
RELEASE=$(get_latest_release)

if [[ -z "$RELEASE" ]]; then
  msg_error "Failed to fetch latest release from GitHub"
  exit 1
fi

ARCH=$(detect_architecture)
DOWNLOAD_URL="https://github.com/zeroclaw-labs/zeroclaw/releases/download/${RELEASE}/zeroclaw-${ARCH}.tar.gz"
TEMP_DIR=$(mktemp -d)

cd "$TEMP_DIR"
if ! curl -fsSLO "$DOWNLOAD_URL"; then
  msg_error "Failed to download ZeroClaw from ${DOWNLOAD_URL}"
  rm -rf "$TEMP_DIR"
  exit 1
fi

if ! tar xzf zeroclaw-*.tar.gz; then
  msg_error "Failed to extract ZeroClaw archive"
  rm -rf "$TEMP_DIR"
  exit 1
fi

install -m 0755 zeroclaw /usr/local/bin/zeroclaw
cd /root
rm -rf "$TEMP_DIR"

msg_ok "Installed ZeroClaw ${RELEASE}"

# Step 3: Ensure /usr/local/bin is in PATH permanently
msg_info "Configuring PATH..."
if ! grep -q '/usr/local/bin' /etc/profile; then
  echo 'export PATH=$PATH:/usr/local/bin' >> /etc/profile
fi
if ! grep -q '/usr/local/bin' /etc/bash.bashrc 2>/dev/null; then
  echo 'export PATH=$PATH:/usr/local/bin' >> /etc/bash.bashrc
fi
# Set for current session
export PATH=$PATH:/usr/local/bin
msg_ok "Added /usr/local/bin to PATH"

# Step 4: Verify binary is accessible
if ! command -v zeroclaw &> /dev/null; then
  msg_error "zeroclaw not found in PATH after installation"
  exit 1
fi
msg_ok "Binary available at: $(which zeroclaw)"

# Step 5: Install bash completions
msg_info "Installing bash completions..."
mkdir -p /etc/bash_completion.d
if zeroclaw completions bash > /etc/bash_completion.d/zeroclaw 2>/dev/null; then
  msg_ok "Installed bash completions to /etc/bash_completion.d/zeroclaw"
else
  msg_info "Completions not available in this version (skipping)"
fi

# Step 6: Create necessary directories
msg_info "Creating directories..."
mkdir -p /root/.zeroclaw/memory
mkdir -p /var/log/zeroclaw
msg_ok "Created directories"

# Step 7: Create systemd service
msg_info "Creating systemd service..."
cat > /etc/systemd/system/zeroclaw.service << 'EOF'
[Unit]
Description=ZeroClaw AI Assistant
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/usr/local/bin/zeroclaw daemon
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zeroclaw > /dev/null 2>&1
msg_ok "Created systemd service"

# Step 8: Start service
msg_info "Starting ZeroClaw..."
systemctl start zeroclaw
sleep 2

# Verify service is running
if systemctl is-active --quiet zeroclaw; then
  msg_ok "ZeroClaw service started successfully"
else
  msg_error "ZeroClaw service failed to start"
  echo "  Check logs with: journalctl -u zeroclaw"
fi

# Step 9: Display completion info
echo ""
echo -e "${GREEN}  ✅ ZeroClaw ${RELEASE} installed successfully!${NC}"
echo ""
echo "  📍 Gateway:     http://$(hostname -I | awk '{print $1}'):42617"
echo "  📍 Config:      /root/.zeroclaw/config.toml"
echo "  📍 Memory:      /root/.zeroclaw/memory/"
echo "  📍 Logs:        journalctl -u zeroclaw"
echo ""
echo "  📝 Next steps:"
echo "     1. Run 'zeroclaw onboard' to configure your AI provider"
echo "     2. Source completions: source /etc/bash_completion.d/zeroclaw"
echo ""
echo "  📖 Documentation: https://github.com/zeroclaw-labs/zeroclaw"
echo ""