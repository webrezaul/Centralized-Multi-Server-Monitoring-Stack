#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  setup-ssl.sh — Automated Let's Encrypt SSL Installation using Certbot
#  Run this on your Mother Server (AWS/VPS) to provision/renew SSL certificates.
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENTRAL_DIR="$(dirname "$SCRIPT_DIR")/Mother Server"

echo "════════════════════════════════════════════════════════════════"
echo "  Let's Encrypt SSL Setup & Provisioning"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Please run this script as root (sudo)."
  exit 1
fi

# Detect operating system
OS_TYPE=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_TYPE=$ID
else
  OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]')
fi

# ── 1. Install Certbot ────────────────────────────────────────────────
echo "📦 Checking and installing Certbot if needed..."
if ! command -v certbot &>/dev/null; then
  echo "Certbot not found. Attempting to install..."
  if [[ "$OS_TYPE" =~ ^(ubuntu|debian|raspbian)$ ]]; then
    apt-get update
    apt-get install -y certbot
  elif [[ "$OS_TYPE" =~ ^(centos|rhel|rocky|alma)$ ]]; then
    dnf install -y epel-release
    dnf install -y certbot
  else
    echo "❌ Unsupported OS type: $OS_TYPE"
    echo "Please install Certbot manually, then re-run this script."
    exit 1
  fi
else
  echo "✓ Certbot is already installed."
fi

# ── 2. Determine Domain Name ──────────────────────────────────────────
DOMAIN=""
# Try to pre-fill from .env file
if [ -f "$CENTRAL_DIR/.env" ]; then
  DOMAIN=$(grep -E "^DOMAIN=" "$CENTRAL_DIR/.env" | cut -d'=' -f2)
fi

echo ""
if [ -n "$DOMAIN" ]; then
  read -rp "Enter your domain name (detected: $DOMAIN) [Press Enter to keep]: " INPUT_DOMAIN
  DOMAIN="${INPUT_DOMAIN:-$DOMAIN}"
else
  read -rp "Enter your domain name (e.g. monitor.yourdomain.com): " DOMAIN
fi

if [ -z "$DOMAIN" ]; then
  echo "❌ Error: Domain name cannot be empty."
  exit 1
fi

# Ask for Email for Let's Encrypt notifications
read -rp "Enter email address for urgent renewal notices (e.g. admin@example.com): " EMAIL
if [ -z "$EMAIL" ]; then
  echo "❌ Error: Email address cannot be empty."
  exit 1
fi

# ── 3. Manage Port 80 / Nginx ─────────────────────────────────────────
echo ""
echo "⚙️  Preparing Port 80 for Certbot Standalone verification..."

# Check if Nginx container is running and stop it to free port 80
NGINX_WAS_RUNNING=false
if command -v docker &>/dev/null; then
  if docker ps --format '{{.Names}}' | grep -q "^monitoring-proxy$"; then
    echo "Stopping Nginx reverse proxy container (monitoring-proxy)..."
    docker compose -f "$CENTRAL_DIR/docker-compose.yml" stop nginx
    NGINX_WAS_RUNNING=true
  fi
fi

# Check if port 80 is still in use by any other local process
if lsof -t -i:80 &>/dev/null || ss -tuln | grep -q ":80 "; then
  echo "⚠️  Port 80 is still in use. Certbot standalone verification might fail."
  echo "Please stop any service listening on port 80 before proceeding."
  read -rp "Press Enter once port 80 is free..."
fi

# ── 4. Request Let's Encrypt SSL Certificate ─────────────────────────
echo ""
echo "🔒 Requesting SSL certificate for $DOMAIN..."
certbot certonly --standalone \
  -d "$DOMAIN" \
  --email "$EMAIL" \
  --agree-tos \
  --no-eff-email \
  --non-interactive

# ── 5. Copy and Provision Certificates ────────────────────────────────
echo ""
echo "📂 Provisioning certificates to Mother Server certs folder..."
mkdir -p "$CENTRAL_DIR/certs"

if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
  cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$CENTRAL_DIR/certs/fullchain.pem"
  cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$CENTRAL_DIR/certs/privkey.pem"
  chmod 644 "$CENTRAL_DIR/certs/fullchain.pem" "$CENTRAL_DIR/certs/privkey.pem"
  echo "✅ Certificates successfully copied to $CENTRAL_DIR/certs/"
else
  echo "❌ Error: SSL certificates were not found in /etc/letsencrypt/live/$DOMAIN/"
  echo "Please check Certbot logs in /var/log/letsencrypt/letsencrypt.log"
  # Restart Nginx if we stopped it
  if [ "$NGINX_WAS_RUNNING" = true ]; then
    echo "Restarting Nginx proxy..."
    docker compose -f "$CENTRAL_DIR/docker-compose.yml" start nginx
  fi
  exit 1
fi

# ── 6. Restart Nginx ──────────────────────────────────────────────────
if [ "$NGINX_WAS_RUNNING" = true ] || [ -f "$CENTRAL_DIR/.env" ]; then
  echo ""
  echo "🚀 Starting / Restarting Nginx reverse proxy with new SSL certificates..."
  docker compose -f "$CENTRAL_DIR/docker-compose.yml" up -d nginx
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  SSL Setup Complete!"
echo "  Your site is now available securely at https://$DOMAIN"
echo "════════════════════════════════════════════════════════════════"
