#!/usr/bin/env bash

##############################################################################
# Configuration
##############################################################################

# Path to your SSH private key
SSH_KEY="$HOME/.ssh/<add-your-key-here>"

# SSH username and server IP
SERVER_USER="ubuntu"
SERVER_HOST="<add-your-server-ip-here>"

# Local paths
LOCAL_BINARY="./target/x86_64-unknown-linux-gnu/release/honeypot"                  # Compiled honeypot binary
LOCAL_INSTALL_SCRIPT="./install_honeypot_service.sh"

# Remote locations
REMOTE_DIR="/home/ubuntu"                  # Temporary location for uploads
REMOTE_BINARY_PATH="${REMOTE_DIR}/honeypot"
REMOTE_INSTALL_SCRIPT="${REMOTE_DIR}/install_honeypot_service.sh"

##############################################################################
# 0. Build the binary
##############################################################################

echo "=== Building the honeypot binary... ==="
cargo build --release --target x86_64-unknown-linux-gnu
if [ $? -ne 0 ]; then
  echo "Error: Failed to build the honeypot binary."
  exit 1
fi


##############################################################################
# 1. Upload the new binary
##############################################################################

echo "=== Uploading the honeypot binary to ${SERVER_USER}@${SERVER_HOST}... ==="
scp -i "${SSH_KEY}" "${LOCAL_BINARY}" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_BINARY_PATH}"
if [ $? -ne 0 ]; then
  echo "Error: Failed to upload the honeypot binary."
  exit 1
fi
echo "=== Successfully uploaded binary. ==="

##############################################################################
# 2. Upload the install script
##############################################################################

echo "=== Uploading install script to ${SERVER_USER}@${SERVER_HOST}... ==="
scp -i "${SSH_KEY}" "${LOCAL_INSTALL_SCRIPT}" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_INSTALL_SCRIPT}"
if [ $? -ne 0 ]; then
  echo "Error: Failed to upload install script."
  exit 1
fi
echo "=== Successfully uploaded install script. ==="

##############################################################################
# 3. Run install script remotely
##############################################################################

echo "=== Running install script on the remote server... ==="
ssh -i "${SSH_KEY}" "${SERVER_USER}@${SERVER_HOST}" << EOF
  set -e  # Exit on any command error

  # Make sure script is executable
  chmod +x "${REMOTE_INSTALL_SCRIPT}"

  # Run it with sudo privileges (prompts if needed)
  sudo "${REMOTE_INSTALL_SCRIPT}"

  # Done
EOF

if [ $? -eq 0 ]; then
  echo "=== Deployment successful! ==="
else
  echo "=== Deployment encountered an error. ==="
  exit 1
fi
