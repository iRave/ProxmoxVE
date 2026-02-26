#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: [Contributor]
# License: MIT | https://github.com/iRave/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/zeroclaw-labs/zeroclaw

# ============================================================================
# ZeroClaw Installation Script
# ============================================================================
# Installs ZeroClaw AI assistant infrastructure in an LXC container
# Pre-built binary installation from GitHub releases
# ============================================================================

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

# Step 1: Install dependencies
msg_info "Installing dependencies"
$STD apt update
$STD apt install -y curl git build-essential ca-certificates
msg_ok "Installed dependencies"

# Step 2: Download ZeroClaw binary
msg_info "Downloading ZeroClaw"
RELEASE=$(get_latest_release)

if [[ -z "$RELEASE" ]]; then
  msg_error "Failed to fetch latest release from GitHub"
  exit 1
fi

ARCH=$(detect_architecture)
DOWNLOAD_URL="https://github.com/zeroclaw-labs/zeroclaw/releases/download/${RELEASE}/zeroclaw-${ARCH}.tar.gz"
TEMP_DIR=$(mktemp -d)

cd "$TEMP_DIR"
msg_info "Downloading ${RELEASE} for ${ARCH}"
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
rm -rf "$TEMP_DIR"

msg_ok "Installed ZeroClaw ${RELEASE}"

# Step 3: Create necessary directories
msg_info "Creating directories"
mkdir -p /root/.zeroclaw/memory
mkdir -p /var/log/zeroclaw
msg_ok "Created directories"

# Step 4: Create systemd service
msg_info "Creating systemd service"
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

# Security hardening
NoNewPrivileges=false
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/root/.zeroclaw /var/log/zeroclaw

# Resource limits (optional, adjust as needed)
# MemoryMax=2G
# CPUQuota=200%

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zeroclaw
msg_ok "Created systemd service"

# Step 5: Interactive onboarding (skip if non-interactive mode)
if [[ "${ZEROCALW_SKIP_ONBOARD:-no}" != "yes" && -t 0 ]]; then
  msg_info "\n${YW}=== ZeroClaw Setup ===${CL}\n"
  
  # Check if config already exists
  if [[ -f /root/.zeroclaw/config.toml ]]; then
    msg_ok "Config already exists at /root/.zeroclaw/config.toml"
    echo -e "${YW}Run 'zeroclaw onboard --force' to reconfigure${CL}"
  else
    echo -e "${YW}This will configure your AI provider.${CL}"
    echo -e "${YW}You can also run 'zeroclaw onboard' manually later.${CL}\n"
    
    read -p "$(echo -e ${GN}Enter your API key \(e.g., sk-...\): ${CL})" API_KEY
    read -p "$(echo -e ${GN}Enter provider [openrouter/openai/anthropic] \(default: openrouter\): ${CL})" PROVIDER
    PROVIDER=${PROVIDER:-openrouter}
    
    if [[ -n "$API_KEY" ]]; then
      msg_info "Running onboarding"
      /usr/local/bin/zeroclaw onboard --api-key "$API_KEY" --provider "$PROVIDER" --force 2>/dev/null || true
      msg_ok "Onboarding completed"
      
      # Optional: Channel setup prompt
      echo -e "\n${YW}=== Channel Setup (Optional) ===${CL}"
      read -p "$(echo -e ${GN}Configure Telegram channel? [y/N]: ${CL})" DO_TELEGRAM
      
      if [[ "$DO_TELEGRAM" =~ ^[Yy]$ ]]; then
        read -p "$(echo -e ${GN}Enter Telegram bot token: ${CL})" TG_TOKEN
        read -p "$(echo -e ${GN}Enter allowed Telegram user ID: ${CL})" TG_USER
        
        if [[ -n "$TG_TOKEN" && -n "$TG_USER" ]]; then
          # Update config.toml with Telegram settings
          if [[ -f /root/.zeroclaw/config.toml ]]; then
            echo -e "\n# Telegram channel configuration" >> /root/.zeroclaw/config.toml
            echo -e "[channels_config.telegram]" >> /root/.zeroclaw/config.toml
            echo -e "enabled = true" >> /root/.zeroclaw/config.toml
            echo -e "bot_token = \"$TG_TOKEN\"" >> /root/.zeroclaw/config.toml
            echo -e "allowed_users = [\"$TG_USER\"]" >> /root/.zeroclaw/config.toml
            msg_ok "Telegram channel configured"
          fi
        fi
      fi
    else
      msg_ok "Skipped onboarding - run 'zeroclaw onboard' manually"
    fi
  fi
else
  msg_ok "Non-interactive mode - skipping onboarding"
  echo -e "${YW}Run 'zeroclaw onboard' to configure after first start${CL}"
fi

# Step 6: Start service
msg_info "Starting ZeroClaw"
systemctl start zeroclaw
sleep 2

# Verify service is running
if systemctl is-active --quiet zeroclaw; then
  msg_ok "ZeroClaw service started successfully"
else
  msg_error "ZeroClaw service failed to start"
  echo -e "${YW}Check logs with: journalctl -u zeroclaw${CL}"
fi

# Step 7: Display completion info
echo -e ""
msg_ok "ZeroClaw ${RELEASE} installed successfully!\n"
echo -e "${TAB}${YW}Gateway:     ${BGN}http://$(hostname -I | awk '{print $1}'):42617${CL}"
echo -e "${TAB}${YW}Config:      ${BGN}/root/.zeroclaw/config.toml${CL}"
echo -e "${TAB}${YW}Memory:      ${BGN}/root/.zeroclaw/memory/${CL}"
echo -e "${TAB}${YW}Logs:        ${BGN}journalctl -u zeroclaw${CL}"
echo -e ""
echo -e "${YW}Useful commands:${CL}"
echo -e "${TAB}  ${BGN}zeroclaw status${CL}           - Check service status"
echo -e "${TAB}  ${BGN}zeroclaw onboard${CL}         - Run interactive setup"
echo -e "${TAB}  ${BGN}zeroclaw agent -m 'Hello'${CL} - Send a test message"
echo -e "${TAB}  ${BGN}zeroclaw --help${CL}           - Show all commands"
echo -e ""
echo -e "${YW}Documentation: ${BGN}https://github.com/zeroclaw-labs/zeroclaw${CL}\n"