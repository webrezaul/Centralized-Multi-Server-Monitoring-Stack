#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  install-docker.sh — Automated Docker & Docker Compose Installer
#  Supports Debian/Ubuntu and CentOS/RHEL/Rocky Linux/Alma Linux
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

echo "════════════════════════════════════════════════════════════════"
echo "  Docker & Docker Compose Installer"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Please run this script as root (sudo)."
  exit 1
fi

# Check if Docker is already installed
if command -v docker &>/dev/null; then
  echo "✓ Docker is already installed: $(docker --version)"
  if docker compose version &>/dev/null; then
    echo "✓ Docker Compose plugin is already installed: $(docker compose version)"
  fi
  exit 0
fi

# Detect OS distribution
OS_DISTRO=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_DISTRO=$ID
fi

case "$OS_DISTRO" in
  ubuntu|debian|pop|mint)
    echo "⚙️  Detected Debian-based system ($OS_DISTRO). Setting up APT repository..."
    apt-get update -y
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$OS_DISTRO/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

    # Add repository to APT sources
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_DISTRO \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ;;

  centos|rhel|rocky|alma)
    echo "⚙️  Detected RHEL-based system ($OS_DISTRO). Setting up YUM repository..."
    yum install -y yum-utils
    yum-config-manager --add-repo "https://download.docker.com/linux/$OS_DISTRO/docker-ce.repo"
    
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ;;

  *)
    echo "⚠️  Unsupported OS: $OS_DISTRO."
    echo "⚙️  Attempting installation via official convenience script..."
    curl -fsSL https://get.docker.com | sh
    ;;
esac

# Start and enable Docker service
echo "⚙️  Starting and enabling Docker service..."
systemctl daemon-reload
systemctl start docker
systemctl enable docker

# Configure non-root user access (add real user if running via sudo)
SUDO_USER_NAME="${SUDO_USER:-}"
if [ -n "$SUDO_USER_NAME" ] && [ "$SUDO_USER_NAME" != "root" ]; then
  echo "⚙️  Adding user '$SUDO_USER_NAME' to the 'docker' group..."
  usermod -aG docker "$SUDO_USER_NAME"
  echo "⚠️  Please log out and log back in (or run 'newgrp docker') for group changes to take effect."
fi

echo ""
echo "✅ Docker & Docker Compose installed successfully!"
echo "   Docker version: $(docker --version)"
echo "   Docker Compose version: $(docker compose version)"
echo "════════════════════════════════════════════════════════════════"
