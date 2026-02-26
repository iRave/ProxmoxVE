#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: [Contributor]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/zeroclaw-labs/zeroclaw

# ============================================================================
# APP CONFIGURATION
# ============================================================================
# ZeroClaw: Fast, small, and fully autonomous AI assistant infrastructure
# Runs on $10 hardware with <5MB RAM - 99% less memory than OpenClaw
# ============================================================================

APP="ZeroClaw"
var_tags="${var_tags:-ai;automation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-no}"

# ============================================================================
# INITIALIZATION
# ============================================================================
header_info "$APP"
variables
color
catch_errors

# ============================================================================
# UPDATE SCRIPT
# ============================================================================
function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Step 1: Verify installation exists
  if [[ ! -f /usr/local/bin/zeroclaw ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Step 2: Get current and latest versions
  CURRENT_VERSION=$(/usr/local/bin/zeroclaw --version 2>/dev/null | head -1 || echo "unknown")
  RELEASE=$(curl -fsSL https://api.github.com/repos/zeroclaw-labs/zeroclaw/releases/latest 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4 || echo "unknown")

  if [[ -z "$RELEASE" || "$RELEASE" == "unknown" ]]; then
    msg_error "Could not fetch latest release information"
    exit
  fi

  if [[ "$CURRENT_VERSION" == "$RELEASE" ]]; then
    msg_ok "${APP} is already up to date (${CURRENT_VERSION})"
    exit
  fi

  # Step 3: Stop service
  msg_info "Stopping ${APP} Service"
  systemctl stop zeroclaw
  msg_ok "Stopped Service"

  # Step 4: Backup binary (just in case)
  msg_info "Backing up current binary"
  cp /usr/local/bin/zeroclaw /usr/local/bin/zeroclaw.bak
  msg_ok "Backed up binary"

  # Step 5: Download and install new version
  msg_info "Updating ${APP} from ${CURRENT_VERSION} to ${RELEASE}"

  # Detect architecture
  ARCH=$(uname -m)
  case $ARCH in
    x86_64) BINARY_ARCH="x86_64" ;;
    aarch64) BINARY_ARCH="aarch64" ;;
    armv7l) BINARY_ARCH="armv7" ;;
    *)
      msg_error "Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac

  DOWNLOAD_URL="https://github.com/zeroclaw-labs/zeroclaw/releases/download/${RELEASE}/zeroclaw-${BINARY_ARCH}-unknown-linux-gnu.tar.gz"
  TEMP_DIR=$(mktemp -d)

  cd "$TEMP_DIR"
  if ! curl -fsSLO "$DOWNLOAD_URL"; then
    msg_error "Failed to download ${RELEASE}"
    mv /usr/local/bin/zeroclaw.bak /usr/local/bin/zeroclaw
    systemctl start zeroclaw
    exit 1
  fi

  if ! tar xzf zeroclaw-*.tar.gz; then
    msg_error "Failed to extract archive"
    mv /usr/local/bin/zeroclaw.bak /usr/local/bin/zeroclaw
    systemctl start zeroclaw
    exit 1
  fi

  install -m 0755 zeroclaw /usr/local/bin/zeroclaw
  rm -rf "$TEMP_DIR"
  rm -f /usr/local/bin/zeroclaw.bak

  msg_ok "Updated ${APP} to ${RELEASE}"

  # Step 6: Restart service
  msg_info "Starting ${APP} Service"
  systemctl start zeroclaw
  msg_ok "Started Service"

  msg_ok "Updated successfully!"
  exit
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
start
build_container
description

# ============================================================================
# COMPLETION MESSAGE
# ============================================================================
msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access ZeroClaw:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:42617${CL}"
echo -e ""
echo -e "${INFO}${YW}Configuration:${CL}"
echo -e "${TAB}  Config file: ${BGN}/root/.zeroclaw/config.toml${CL}"
echo -e "${TAB}  Memory:      ${BGN}/root/.zeroclaw/memory/${CL}"
echo -e ""
echo -e "${INFO}${YW}Useful commands:${CL}"
echo -e "${TAB}  ${BGN}zeroclaw onboard${CL}    - Run interactive setup"
echo -e "${TAB}  ${BGN}zeroclaw status${CL}      - Check service status"
echo -e "${TAB}  ${BGN}zeroclaw agent -m ' Hello'${CL}  - Send a message"
echo -e "${TAB}  ${BGN}zeroclaw --help${CL}      - Show all commands"