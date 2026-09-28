#!/usr/bin/env bash

set -euo pipefail

# Ensure the script is run with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root or with sudo." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "=========================================================="
echo " Installing Nginx, Docker Engine, Docker Compose & Certbot"
echo "=========================================================="

# 1. Update package list and install base utilities
echo "[1/5] Updating packages and installing prerequisites..."
apt-get update -y
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    ufw

# 2. Install Nginx
echo "[2/5] Installing Nginx..."
apt-get install -y nginx
systemctl enable nginx
systemctl restart nginx

# 3. Install Docker from official Docker repository
echo "[3/5] Installing Docker CE and Docker Compose plugin..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

UBUNTU_CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
ARCH="$(dpkg --print-architecture)"

echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

systemctl enable docker
systemctl restart docker

# Add invoking non-root sudo user to the docker group if present
TARGET_USER="${SUDO_USER:-}"
if [ -n "${TARGET_USER}" ] && [ "${TARGET_USER}" != "root" ]; then
    echo "Adding '${TARGET_USER}' to the 'docker' group..."
    usermod -aG docker "${TARGET_USER}"
    echo "Note: Log out and back in (or run 'newgrp docker') for docker group permissions to take effect."
fi

# 4. Install Certbot and Nginx plugin
echo "[4/5] Installing Certbot and python3-certbot-nginx..."
apt-get install -y certbot python3-certbot-nginx

# 5. Configure Firewall (UFW)
echo "[5/5] Configuring basic UFW firewall rules..."
ufw allow OpenSSH || true
ufw allow 'Nginx Full' || true

if ! ufw status | grep -q "Status: active"; then
    echo "Note: UFW is installed and rules are added (OpenSSH, Nginx Full). To enable: sudo ufw enable"
fi

echo "=========================================================="
echo " Installation Summary & Verification"
echo "=========================================================="
echo "Nginx:"
nginx -v || true
echo ""
echo "Docker:"
docker --version || true
docker compose version || true
echo ""
echo "Certbot:"
certbot --version || true
echo "=========================================================="
echo "Installation complete!"
