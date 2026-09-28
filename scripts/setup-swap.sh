#!/usr/bin/env bash

set -euo pipefail

# Configuration
SWAP_FILE="/swapfile"
SWAP_SIZE="8G"
SWAPPINESS_VALUE=10
VFS_CACHE_PRESSURE_VALUE=50

# Ensure the script is run with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root or with sudo." >&2
    exit 1
fi

echo "=== Setting up ${SWAP_SIZE} Swap on Ubuntu ==="

# 1. Check existing swap
echo "[1/6] Checking existing swap..."
swapon --show

if swapon --show | grep -q "${SWAP_FILE}"; then
    echo "Swap file '${SWAP_FILE}' is already active."
    free -h
    exit 0
fi

if [ -f "${SWAP_FILE}" ]; then
    echo "Warning: '${SWAP_FILE}' already exists. Backing it up / replacing..."
    swapoff "${SWAP_FILE}" 2>/dev/null || true
    rm -f "${SWAP_FILE}"
fi

# 2. Allocate space for the swap file
echo "[2/6] Allocating ${SWAP_SIZE} for ${SWAP_FILE}..."
if ! fallocate -l "${SWAP_SIZE}" "${SWAP_FILE}" 2>/dev/null; then
    echo "fallocate failed, falling back to dd (this might take a minute)..."
    dd if=/dev/zero of="${SWAP_FILE}" bs=1M count=8192 status=progress
fi

# 3. Secure file permissions
echo "[3/6] Setting permissions to 600..."
chmod 600 "${SWAP_FILE}"

# 4. Format and activate swap
echo "[4/6] Initializing and enabling swap..."
mkswap "${SWAP_FILE}"
swapon "${SWAP_FILE}"

# 5. Persist swap in /etc/fstab
echo "[5/6] Updating /etc/fstab for persistence across reboots..."
if ! grep -q "^${SWAP_FILE}[[:space:]]" /etc/fstab; then
    cp /etc/fstab /etc/fstab.bak."$(date +%Y%m%d%H%M%S)"
    echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
    echo "Added entry to /etc/fstab."
else
    echo "Entry for ${SWAP_FILE} already exists in /etc/fstab."
fi

# 6. Optimize swap performance settings (swappiness & cache pressure)
echo "[6/6] Tuning sysctl swappiness and cache pressure..."
SYSCTL_FILE="/etc/sysctl.d/99-swap.conf"
cat > "${SYSCTL_FILE}" <<EOF
vm.swappiness=${SWAPPINESS_VALUE}
vm.vfs_cache_pressure=${VFS_CACHE_PRESSURE_VALUE}
EOF

sysctl --system > /dev/null 2>&1 || sysctl -p "${SYSCTL_FILE}" > /dev/null 2>&1 || true

echo "=== Swap setup completed successfully! ==="
echo ""
echo "Current Swap Status:"
swapon --show
echo ""
echo "Memory Overview:"
free -h
