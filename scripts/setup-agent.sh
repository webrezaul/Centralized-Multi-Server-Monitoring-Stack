#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  setup-agent.sh — Interactive setup for a monitored server agent
#  Run this on each server you want to monitor (Hostinger, AWS, VPS, etc.)
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Select which child agent to configure:"
echo "1) Child server 1 (Hostinger VPS)"
echo "2) Child-server2 (Server 3)"
read -rp "Choice [1-2]: " CHILD_CHOICE
if [ "$CHILD_CHOICE" = "1" ]; then
  AGENT_DIR="$(dirname "$SCRIPT_DIR")/Child server 1"
else
  AGENT_DIR="$(dirname "$SCRIPT_DIR")/Child-server2"
fi

echo "════════════════════════════════════════════════════════════════"
echo "  Monitoring Agent Setup"
echo "════════════════════════════════════════════════════════════════"
echo ""

# ── 1. Collect configuration ──────────────────────────────────────────
read -rp "Server name (unique label, e.g. hostinger-1, aws-1, vps-3): " SERVER_NAME
read -rp "Central hub URL (e.g. https://monitor.yourdomain.com): " CENTRAL_URL
read -rp "Auth username [agent_user]: " AUTH_USER
AUTH_USER="${AUTH_USER:-agent_user}"
read -rsp "Auth password: " AUTH_PASS
echo ""

# ── 2. Generate .env file ─────────────────────────────────────────────
cat > "$AGENT_DIR/.env" <<EOF
SERVER_NAME=${SERVER_NAME}
CENTRAL_URL=${CENTRAL_URL}
AUTH_USER=${AUTH_USER}
AUTH_PASS=${AUTH_PASS}
EOF
chmod 600 "$AGENT_DIR/.env"
echo ""
echo "✓ Generated $AGENT_DIR/.env"

# ── 3. Replace placeholders in config files ───────────────────────────
# Prometheus agent config
sed -i "s|\${SERVER_NAME}|${SERVER_NAME}|g" "$AGENT_DIR/prometheus-agent.yml"
sed -i "s|\${CENTRAL_URL}|${CENTRAL_URL}|g" "$AGENT_DIR/prometheus-agent.yml"
sed -i "s|\${AUTH_USER}|${AUTH_USER}|g" "$AGENT_DIR/prometheus-agent.yml"
sed -i "s|\${AUTH_PASS}|${AUTH_PASS}|g" "$AGENT_DIR/prometheus-agent.yml"

# Promtail config
sed -i "s|\${SERVER_NAME}|${SERVER_NAME}|g" "$AGENT_DIR/promtail-config.yml"
sed -i "s|\${CENTRAL_URL}|${CENTRAL_URL}|g" "$AGENT_DIR/promtail-config.yml"
sed -i "s|\${AUTH_USER}|${AUTH_USER}|g" "$AGENT_DIR/promtail-config.yml"
sed -i "s|\${AUTH_PASS}|${AUTH_PASS}|g" "$AGENT_DIR/promtail-config.yml"

echo "✓ Configured prometheus-agent.yml and promtail-config.yml for server: ${SERVER_NAME}"

# ── 4. Verify Docker is available ─────────────────────────────────────
echo ""
if command -v docker &>/dev/null; then
    echo "✓ Docker found: $(docker --version)"
    if command -v docker compose &>/dev/null || docker compose version &>/dev/null 2>&1; then
        echo "✓ Docker Compose found"
    else
        echo "⚠ Docker Compose not found. Install it: https://docs.docker.com/compose/install/"
    fi
else
    echo "⚠ Docker not found! Install Docker first:"
    echo "  curl -fsSL https://get.docker.com | sh"
    echo "  sudo usermod -aG docker \$USER"
fi

# ── 5. Start the agent ────────────────────────────────────────────────
echo ""
read -rp "Start the monitoring agent now? [Y/n]: " DO_START
DO_START="${DO_START:-Y}"
if [[ "$DO_START" =~ ^[Yy]$ ]]; then
    cd "$AGENT_DIR"
    docker compose up -d
    echo ""
    echo "✓ Agent is starting! Check status with: docker compose ps"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Server:        ${SERVER_NAME}"
    echo "  Pushing to:    ${CENTRAL_URL}"
    echo "  Node Exporter: http://localhost:9100/metrics"
    echo "  cAdvisor:      http://localhost:8080"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Verify in Grafana: Explore → Prometheus → node_load1{server=\"${SERVER_NAME}\"}"
else
    echo ""
    echo "To start manually: cd $AGENT_DIR && docker compose up -d"
fi
