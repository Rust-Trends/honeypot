#!/usr/bin/env bash
#
# install_honeypot_service.sh
#
# Idempotent script to install/upgrade the 'honeypot' systemd service.
# Safe to run multiple times.
#
# Steps:
# 1. Create 'honeypot' user if missing
# 2. Create /opt/honeypot dir if missing
# 3. Copy local binary to /opt/honeypot if it differs
# 4. Create or update systemd unit file
# 5. Reload & restart service

set -euo pipefail

###############################################################################
# Configurable parameters
###############################################################################
SERVICE_NAME="honeypot"
HONEYPOT_USER="honeypot"
HONEYPOT_GROUP="honeypot"
INSTALL_DIR="/opt/honeypot"
BINARY_NAME="honeypot"              # The name of your compiled binary
LOCAL_BINARY_PATH="./honeypot"      # Where your compiled binary is locally
SYSTEMD_UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
PERMISSIONS="750"                   # Permissions for $INSTALL_DIR

###############################################################################
# 1. Create user and group if they do not exist
###############################################################################
echo ">> Checking if user '$HONEYPOT_USER' exists..."
if id "$HONEYPOT_USER" &>/dev/null; then
  echo "   User '$HONEYPOT_USER' already exists."
else
  echo "   Creating system user '$HONEYPOT_USER'..."
  sudo useradd -r -s /usr/sbin/nologin "$HONEYPOT_USER"
fi

###############################################################################
# 2. Create /opt/honeypot directory if missing
###############################################################################
echo ">> Ensuring $INSTALL_DIR directory exists..."
if [ ! -d "$INSTALL_DIR" ]; then
  echo "   Creating directory $INSTALL_DIR..."
  sudo mkdir -p "$INSTALL_DIR"
  sudo chown "$HONEYPOT_USER":"$HONEYPOT_GROUP" "$INSTALL_DIR"
  sudo chmod "$PERMISSIONS" "$INSTALL_DIR"
else
  echo "   Directory $INSTALL_DIR already exists."
  echo "   Ensuring correct ownership & permissions..."
  sudo chown "$HONEYPOT_USER":"$HONEYPOT_GROUP" "$INSTALL_DIR"
  sudo chmod "$PERMISSIONS" "$INSTALL_DIR"
fi

###############################################################################
# 3. Copy binary to /opt/honeypot if it differs
###############################################################################
echo ">> Checking if $BINARY_NAME needs to be updated..."
LOCAL_CHECKSUM=$(sha256sum "$LOCAL_BINARY_PATH" | awk '{print $1}')
REMOTE_PATH="$INSTALL_DIR/$BINARY_NAME"

if [ -f "$REMOTE_PATH" ]; then
  REMOTE_CHECKSUM=$(sudo sha256sum "$REMOTE_PATH" | awk '{print $1}')
  if [ "$LOCAL_CHECKSUM" = "$REMOTE_CHECKSUM" ]; then
    echo "   Binary already matches the existing one; no copy needed."
  else
    # Verify if the service is already running
    # If it is, we need to stop it first
    if sudo systemctl is-active --quiet "$SERVICE_NAME.service"; then
        echo ">> Stopping $SERVICE_NAME service..."
        sudo systemctl stop "$SERVICE_NAME.service"
    fi
  
    echo "   Copying updated binary to $REMOTE_PATH..."
    sudo cp "$LOCAL_BINARY_PATH" "$REMOTE_PATH"
    sudo chown "$HONEYPOT_USER":"$HONEYPOT_GROUP" "$REMOTE_PATH"
    sudo chmod +x "$REMOTE_PATH"
  fi
else
  # Verify if the service is already running
  # If it is, we need to stop it first
  if sudo systemctl is-active --quiet "$SERVICE_NAME.service"; then
    echo ">> Stopping $SERVICE_NAME service..."
    sudo systemctl stop "$SERVICE_NAME.service"
  fi

  echo "   No existing binary at $REMOTE_PATH, copying now..."
  sudo cp "$LOCAL_BINARY_PATH" "$REMOTE_PATH"
  sudo chown "$HONEYPOT_USER":"$HONEYPOT_GROUP" "$REMOTE_PATH"
  sudo chmod +x "$REMOTE_PATH"
fi

###############################################################################
# 4. Create or update systemd service file
###############################################################################
echo ">> Installing or updating systemd unit file at $SYSTEMD_UNIT_PATH..."
SERVICE_FILE_CONTENT="[Unit]
Description=Honeypot Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/honeypot
User=${HONEYPOT_USER}
Group=${HONEYPOT_GROUP}
ExecStart=${REMOTE_PATH}
StandardOutput=file:/var/log/honeypot.log
StandardError=file:/var/log/honeypot_err.log
Restart=on-failure

[Install]
WantedBy=multi-user.target
"

# If the file doesn't exist OR the content differs, overwrite it
if [ -f "$SYSTEMD_UNIT_PATH" ]; then
  CURRENT_CONTENT=$(sudo cat "$SYSTEMD_UNIT_PATH")
  if [ "$CURRENT_CONTENT" != "$SERVICE_FILE_CONTENT" ]; then
    echo "   Updating systemd service file because content changed..."
    echo "$SERVICE_FILE_CONTENT" | sudo tee "$SYSTEMD_UNIT_PATH" >/dev/null
  else
    echo "   Systemd unit file already up-to-date."
  fi
else
  echo "   Creating new systemd service file..."
  echo "$SERVICE_FILE_CONTENT" | sudo tee "$SYSTEMD_UNIT_PATH" >/dev/null
fi

###############################################################################
# 5. Reload & restart systemd service
###############################################################################
echo ">> Reloading systemd daemon..."
sudo systemctl daemon-reload

echo ">> Enabling $SERVICE_NAME service to start on boot..."
sudo systemctl enable "$SERVICE_NAME.service"

echo ">> Restarting $SERVICE_NAME service..."
sudo systemctl restart "$SERVICE_NAME.service"

echo ">> Checking $SERVICE_NAME status..."
sudo systemctl status "$SERVICE_NAME.service" --no-pager || true

echo ">> Done! The $SERVICE_NAME service is set up and running."