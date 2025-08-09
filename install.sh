#!/bin/bash

set -e

# Prompt for domain name
echo "Enter your domain name (e.g., mail.example.com):"
read -r DOMAIN_NAME

if [[ -z "$DOMAIN_NAME" ]]; then
    echo "❌ Domain name is required!"
    exit 1
fi

# Constants
GO_VERSION="1.24.4"
GO_TAR="go$GO_VERSION.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/$GO_TAR"
GO_INSTALL_DIR="/usr/local"
GO_PATH="/usr/local/go/bin"
GO_MTA_DIR="/opt/go-mta"
QUEUE_DIR="/var/mailqueue"
BIN_MTA_SERVER="/usr/local/bin/mta-server"
BIN_MTA_QUEUE="/usr/local/bin/mta-queue"
USERS_FILE="users.txt"
DOMAIN_FILE="$GO_MTA_DIR/domain.txt"

# Install Go from official source
install_go() {
  echo "[+] Installing Go $GO_VERSION..."
  rm -rf "$GO_INSTALL_DIR/go"
  wget "$GO_URL"
  tar -C "$GO_INSTALL_DIR" -xzf "$GO_TAR"
  echo "export PATH=\$PATH:$GO_PATH" >> /etc/profile
  export PATH="$PATH:$GO_PATH"
  source /etc/profile
  rm -f "$GO_TAR"
  echo "[+] Go installed and PATH updated."
}

# Prepare directories
prepare_directories() {
  echo "[+] Preparing directories..."
  mkdir -p "$GO_MTA_DIR"
  mkdir -p "$QUEUE_DIR"
  touch "$USERS_FILE"
  chmod 600 "$USERS_FILE"
  
  # Save domain name
  echo "$DOMAIN_NAME" > "$DOMAIN_FILE"
  echo "[+] Domain saved: $DOMAIN_NAME"
}

# Install MTA binaries
install_mta() {
  echo "[+] Copying source code..."
  cp main.go "$GO_MTA_DIR/main.go"
  cp queue.go "$GO_MTA_DIR/queue.go"
  cd "$GO_MTA_DIR"

  echo "[+] Initializing Go module..."
  "$GO_PATH/go" mod init go-mta
  "$GO_PATH/go" get github.com/emersion/go-smtp@v0.15.0

  echo "[+] Building binaries..."
  "$GO_PATH/go" build -o "$BIN_MTA_SERVER" main.go
  "$GO_PATH/go" build -o "$BIN_MTA_QUEUE" queue.go
}


# Create systemd services
create_services() {
  echo "[+] Creating systemd service files..."

  cat <<EOF > /etc/systemd/system/mta-server.service
[Unit]
Description=Go SMTP Server (MTA)
After=network.target

[Service]
ExecStart=$BIN_MTA_SERVER
WorkingDirectory=$GO_MTA_DIR
User=root
Restart=on-failure
StandardOutput=append:/var/log/mta-server.log
StandardError=append:/var/log/mta-server.err



[Install]
WantedBy=multi-user.target
EOF

  cat <<EOF > /etc/systemd/system/mta-queue.service
[Unit]
Description=Go SMTP Delivery Queue Processor
After=network.target

[Service]
ExecStart=$BIN_MTA_QUEUE
WorkingDirectory=$GO_MTA_DIR
Restart=always
RestartSec=5
User=root
StandardOutput=append:/var/log/mta-queue.log
StandardError=append:/var/log/mta-queue.err


[Install]
WantedBy=multi-user.target
EOF

  echo "[+] Reloading and enabling services..."
  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable mta-server.service
  systemctl enable mta-queue.service
  systemctl start mta-server.service
  systemctl start mta-queue.service
  
  # Setup certificate renewal
  echo "[+] Setting up certificate renewal..."
  (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet && systemctl reload mta-server") | crontab -
}

# Install and configure Let's Encrypt
install_letsencrypt() {
  echo "[+] Installing Let's Encrypt..."
  
  # Install certbot
  apt-get update
  apt-get install -y certbot
  
  # Stop any existing web server on port 80
  systemctl stop apache2 2>/dev/null || true
  systemctl stop nginx 2>/dev/null || true
  
  # Get certificate
  echo "[+] Obtaining SSL certificate for $DOMAIN_NAME..."
  certbot certonly --standalone -d "$DOMAIN_NAME" --non-interactive --agree-tos --email info@"$DOMAIN_NAME" --quiet
  
  if [[ $? -eq 0 ]]; then
    echo "[+] SSL certificate obtained successfully!"
  else
    echo "[!] Failed to obtain SSL certificate. Please check your domain DNS settings."
    echo "[!] Make sure $DOMAIN_NAME points to this server's IP address."
    exit 1
  fi
}

# Main
install_go
prepare_directories
install_letsencrypt
install_mta
create_services

echo "[✓] MTA installation completed successfully!"
echo "[✓] SMTP server is now running on port 465 with SSL"
echo "[✓] Domain: $DOMAIN_NAME"
