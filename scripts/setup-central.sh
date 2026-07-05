#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  setup-central.sh — Interactive setup for the Central Monitoring Hub
#  Run this on your AWS/VPS server that will host Grafana, Prometheus, etc.
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENTRAL_DIR="$(dirname "$SCRIPT_DIR")/Mother Server"

echo "════════════════════════════════════════════════════════════════"
echo "  Central Monitoring Hub Setup"
echo "════════════════════════════════════════════════════════════════"
echo ""

# ── 1. Collect configuration ──────────────────────────────────────────
read -rp "Enter your monitoring domain (e.g. monitor.yourdomain.com): " DOMAIN
read -rp "Grafana admin username [admin]: " GF_ADMIN_USER
GF_ADMIN_USER="${GF_ADMIN_USER:-admin}"
read -rsp "Grafana admin password: " GF_ADMIN_PASSWORD
echo ""
read -rp "Agent auth username [agent_user]: " AGENT_AUTH_USER
AGENT_AUTH_USER="${AGENT_AUTH_USER:-agent_user}"
read -rsp "Agent auth password: " AGENT_AUTH_PASS
echo ""
read -rp "Prometheus retention period [30d]: " PROMETHEUS_RETENTION
PROMETHEUS_RETENTION="${PROMETHEUS_RETENTION:-30d}"
read -rp "Alertmanager webhook URL [https://your-power-automate-webhook-url]: " ALERTMANAGER_WEBHOOK_URL
ALERTMANAGER_WEBHOOK_URL="${ALERTMANAGER_WEBHOOK_URL:-https://your-power-automate-webhook-url}"

# ── 2. Generate .env file ─────────────────────────────────────────────
cat > "$CENTRAL_DIR/.env" <<EOF
DOMAIN=${DOMAIN}
GF_ADMIN_USER=${GF_ADMIN_USER}
GF_ADMIN_PASSWORD=${GF_ADMIN_PASSWORD}
AGENT_AUTH_USER=${AGENT_AUTH_USER}
AGENT_AUTH_PASS=${AGENT_AUTH_PASS}
PROMETHEUS_RETENTION=${PROMETHEUS_RETENTION}
ALERTMANAGER_WEBHOOK_URL=${ALERTMANAGER_WEBHOOK_URL}
EOF
chmod 600 "$CENTRAL_DIR/.env"
echo ""
echo "✓ Generated $CENTRAL_DIR/.env"

# ── 3. Update configurations ──────────────────────────────────────────
sed -i "s/grafana\.mdrezaulkarim\.com/${DOMAIN}/g" "$CENTRAL_DIR/nginx.conf"
sed -i "s/monitor\.yourdomain\.com/${DOMAIN}/g" "$CENTRAL_DIR/nginx.conf"
sed -i "s|\${ALERTMANAGER_WEBHOOK_URL}|${ALERTMANAGER_WEBHOOK_URL}|g" "$CENTRAL_DIR/alertmanager.yml"
echo "✓ Updated domain in nginx.conf and webhook in alertmanager.yml"

# ── 4. Set up TLS certificate ─────────────────────────────────────────
echo ""
echo "── TLS Certificate Setup ──────────────────────────────────────"
if command -v certbot &>/dev/null; then
    read -rp "Run certbot to get a TLS certificate? [Y/n]: " DO_CERTBOT
    DO_CERTBOT="${DO_CERTBOT:-Y}"
    if [[ "$DO_CERTBOT" =~ ^[Yy]$ ]]; then
        echo "Stopping any service on port 80..."
        sudo certbot certonly --standalone -d "$DOMAIN"
        mkdir -p "$CENTRAL_DIR/certs"
        sudo cp "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" "$CENTRAL_DIR/certs/"
        sudo cp "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" "$CENTRAL_DIR/certs/"
        sudo chmod 644 "$CENTRAL_DIR/certs/"*.pem
        echo "✓ TLS certificates copied to $CENTRAL_DIR/certs/"
    fi
else
    echo "⚠ certbot not found. Install it with: sudo apt install certbot"
    echo "  Then run: sudo certbot certonly --standalone -d $DOMAIN"
    echo "  Copy fullchain.pem and privkey.pem into $CENTRAL_DIR/certs/"
    mkdir -p "$CENTRAL_DIR/certs"
fi

# ── 5. Create htpasswd file ───────────────────────────────────────────
echo ""
echo "── Basic Auth Setup ───────────────────────────────────────────"
if command -v htpasswd &>/dev/null; then
    htpasswd -cb "$CENTRAL_DIR/htpasswd" "$AGENT_AUTH_USER" "$AGENT_AUTH_PASS"
    echo "✓ Created htpasswd file"
elif command -v openssl &>/dev/null; then
    HASH=$(openssl passwd -apr1 "$AGENT_AUTH_PASS")
    echo "${AGENT_AUTH_USER}:${HASH}" > "$CENTRAL_DIR/htpasswd"
    echo "✓ Created htpasswd file (via openssl)"
else
    echo "⚠ Neither htpasswd nor openssl found."
    echo "  Install apache2-utils: sudo apt install apache2-utils"
    echo "  Then run: htpasswd -c $CENTRAL_DIR/htpasswd $AGENT_AUTH_USER"
fi

# ── 6. Start the stack ────────────────────────────────────────────────
echo ""
echo "── Starting Services ──────────────────────────────────────────"
read -rp "Start the monitoring stack now? [Y/n]: " DO_START
DO_START="${DO_START:-Y}"
if [[ "$DO_START" =~ ^[Yy]$ ]]; then
    cd "$CENTRAL_DIR"
    docker compose up -d
    echo ""
    echo "✓ Stack is starting! Check status with: docker compose ps"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Grafana:       https://${DOMAIN}"
    echo "  Prometheus:    http://localhost:9090 (internal only)"
    echo "  Loki:          http://localhost:3100 (internal only)"
    echo "  Alertmanager:  http://localhost:9093 (internal only)"
    echo "════════════════════════════════════════════════════════════════"
else
    echo ""
    echo "To start manually: cd $CENTRAL_DIR && docker compose up -d"
fi
