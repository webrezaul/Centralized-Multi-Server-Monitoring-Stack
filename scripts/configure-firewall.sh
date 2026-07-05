#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  configure-firewall.sh — Automatic firewall port configuration
#  Supports both UFW (Debian/Ubuntu) and Firewalld (CentOS/RHEL/Rocky/Alma)
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

echo "════════════════════════════════════════════════════════════════"
echo "  Firewall Configuration Helper"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Please run this script as root (sudo)."
  exit 1
fi

# Detect firewall tool
FIREWALL_TOOL=""
if command -v ufw &>/dev/null; then
  FIREWALL_TOOL="ufw"
elif command -v firewall-cmd &>/dev/null; then
  FIREWALL_TOOL="firewalld"
else
  echo "⚠️  No standard firewall management tool (ufw or firewalld) detected."
  echo "   If this is AWS EC2, configure ports in your AWS Security Group instead."
  echo "   If this is Hostinger, configure ports in the Hostinger VPS panel."
  exit 0
fi

echo "✓ Detected firewall manager: $FIREWALL_TOOL"
echo ""
echo "Select the server type to configure:"
echo "1) Mother Server (Central Hub - runs Grafana, Loki, Prometheus)"
echo "2) Satellite Agent Server (Hostinger / Server 3)"
read -rp "Enter choice [1-2]: " SERVER_TYPE

case "$SERVER_TYPE" in
  1)
    echo ""
    echo "── Configuring Mother Server Inbound Ports (80, 443, 22) ──────"
    if [ "$FIREWALL_TOOL" = "ufw" ]; then
      # Allow standard ports
      ufw allow 22/tcp comment 'SSH'
      ufw allow 80/tcp comment 'HTTP'
      ufw allow 443/tcp comment 'HTTPS'
      
      # Allow direct access ports
      ufw allow 3000/tcp comment 'Grafana'
      ufw allow 9090/tcp comment 'Prometheus'
      ufw allow 3100/tcp comment 'Loki'
      ufw allow 9093/tcp comment 'Alertmanager'
      
      # Enable UFW if disabled
      if ! ufw status | grep -q "active"; then
        echo "⚠️  UFW is currently disabled. Enabling it..."
        ufw --force enable
      fi
      ufw status verbose
    elif [ "$FIREWALL_TOOL" = "firewalld" ]; then
      # Allow services
      firewall-cmd --permanent --add-service=ssh
      firewall-cmd --permanent --add-service=http
      firewall-cmd --permanent --add-service=https
      firewall-cmd --permanent --add-port=3000/tcp
      firewall-cmd --permanent --add-port=9090/tcp
      firewall-cmd --permanent --add-port=3100/tcp
      firewall-cmd --permanent --add-port=9093/tcp
      firewall-cmd --reload
      firewall-cmd --list-all
    fi
    echo ""
    echo "✅ Mother Server firewall configured successfully."
    echo "   Opened ports: 22 (SSH), 80 (HTTP), 443 (HTTPS), 3000 (Grafana), 9090 (Prometheus), 3100 (Loki), 9093 (Alertmanager)."
    ;;

  2)
    echo ""
    echo "── Configuring Satellite Agent Inbound Ports (22 only) ─────────"
    echo "ℹ️  Note: Push-based architecture requires NO inbound monitoring ports."
    echo "   Exporters (node-exporter, cAdvisor) listen locally on 127.0.0.1"
    echo "   and are only accessible by the local Prometheus Agent container."
    echo ""
    read -rp "Do you want to secure this agent by closing all ports except SSH (22)? [y/N]: " SECURE_AGENT
    SECURE_AGENT="${SECURE_AGENT:-n}"
    
    if [[ "$SECURE_AGENT" =~ ^[Yy]$ ]]; then
      if [ "$FIREWALL_TOOL" = "ufw" ]; then
        # Default deny inbound, allow SSH
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp comment 'SSH'
        
        if ! ufw status | grep -q "active"; then
          echo "⚠️  UFW is currently disabled. Enabling it..."
          ufw --force enable
        fi
        ufw status verbose
      elif [ "$FIREWALL_TOOL" = "firewalld" ]; then
        # Ensure SSH is open, default zone blocks others
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --reload
        firewall-cmd --list-all
      fi
      echo ""
      echo "✅ Agent Server firewall configured successfully."
      echo "   All inbound ports blocked except port 22 (SSH)."
    else
      echo "   Skipped configuration. Ensure port 22 (SSH) is kept open."
    fi
    ;;

  *)
    echo "❌ Invalid choice."
    exit 1
    ;;
esac
