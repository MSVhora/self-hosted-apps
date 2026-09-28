#!/usr/bin/env bash

set -euo pipefail

# Ensure script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root or with sudo." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Arguments / Flags defaults
APPS_TO_INSTALL=""
SOLIDTIME_DOMAIN=""
IT_TOOLS_DOMAIN=""
EMAIL=""

# Parse command line flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apps)
            APPS_TO_INSTALL="$2"
            shift 2
            ;;
        --solidtime-domain)
            SOLIDTIME_DOMAIN="$2"
            shift 2
            ;;
        --it-tools-domain|--it-domain)
            IT_TOOLS_DOMAIN="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: sudo $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --apps <list>             Comma-separated list of apps to install ('all', 'solidtime', 'it-tools', 'none')"
            echo "  --solidtime-domain <dom>  Domain name for Solidtime (e.g., time.picmix.in)"
            echo "  --it-tools-domain <dom>   Domain name for IT-Tools (e.g., tools.picmix.in)"
            echo "  --email <email>           Email address for Let's Encrypt / Certbot SSL registration"
            echo "  -h, --help                Show this help message"
            exit 0
            ;;
        *)
            # Backward compatibility: First positional arg treated as email if not flag
            if [ -z "${EMAIL}" ] && [[ "$1" == *"@"* ]]; then
                EMAIL="$1"
            fi
            shift
            ;;
    esac
done

echo "=========================================================="
echo " Server Provisioning & Application Bootstrap"
echo "=========================================================="

# 1. Setup 8GB Swap
echo ""
echo ">>> [Step 1/3] Setting up Swap Memory..."
bash "${SCRIPT_DIR}/setup-swap.sh"

# 2. Install Core Stack (Nginx, Docker CE, Docker Compose, Certbot)
echo ""
echo ">>> [Step 2/3] Installing Core Stack (Docker, Nginx, Certbot)..."
bash "${SCRIPT_DIR}/install-core-stack.sh"

systemctl start docker

# 3. Interactive App Selection (if --apps was not specified via CLI)
if [ -z "${APPS_TO_INSTALL}" ]; then
    if [ -t 0 ]; then
        echo ""
        echo "=========================================================="
        echo " Select Applications to Deploy:"
        echo "=========================================================="
        echo " 1) All Apps (Solidtime + IT-Tools)"
        echo " 2) Solidtime (Time tracking & management)"
        echo " 3) IT-Tools (Developer & IT web utility suite)"
        echo " 4) None (Core server stack only)"
        echo "=========================================================="
        read -rp "Enter choice [1-4] (default: 1): " APP_CHOICE
        APP_CHOICE="${APP_CHOICE:-1}"

        case "${APP_CHOICE}" in
            1) APPS_TO_INSTALL="solidtime,it-tools" ;;
            2) APPS_TO_INSTALL="solidtime" ;;
            3) APPS_TO_INSTALL="it-tools" ;;
            4) APPS_TO_INSTALL="none" ;;
            *) echo "Invalid choice, defaulting to all."; APPS_TO_INSTALL="solidtime,it-tools" ;;
        esac
    else
        APPS_TO_INSTALL="solidtime,it-tools"
    fi
fi

echo ""
echo ">>> [Step 3/3] Deploying Selected Applications: ${APPS_TO_INSTALL}"

# Deploy Solidtime if selected
if [[ "${APPS_TO_INSTALL}" == *"solidtime"* ]] || [[ "${APPS_TO_INSTALL}" == "all" ]]; then
    echo ""
    echo "----------------------------------------------------------"
    echo " Deploying Solidtime..."
    echo "----------------------------------------------------------"
    if [ -z "${SOLIDTIME_DOMAIN}" ] && [ -t 0 ]; then
        read -rp "Enter domain for Solidtime (e.g. time.picmix.in, or press Enter to skip SSL): " SOLIDTIME_DOMAIN
    fi
    bash "${SCRIPT_DIR}/setup-solidtime.sh" "${SOLIDTIME_DOMAIN}" "${EMAIL}"
fi

# Deploy IT-Tools if selected
if [[ "${APPS_TO_INSTALL}" == *"it-tools"* ]] || [[ "${APPS_TO_INSTALL}" == "all" ]]; then
    echo ""
    echo "----------------------------------------------------------"
    echo " Deploying IT-Tools..."
    echo "----------------------------------------------------------"
    if [ -z "${IT_TOOLS_DOMAIN}" ] && [ -t 0 ]; then
        read -rp "Enter domain for IT-Tools (e.g. tools.picmix.in, or press Enter to skip SSL): " IT_TOOLS_DOMAIN
    fi
    bash "${SCRIPT_DIR}/setup-it-tools.sh" "${IT_TOOLS_DOMAIN}" "${EMAIL}"
fi

echo ""
echo "=========================================================="
echo " Bootstrap Process Completed Successfully!"
echo "=========================================================="
if [[ "${APPS_TO_INSTALL}" == *"solidtime"* ]] && [ -n "${SOLIDTIME_DOMAIN}" ]; then
    echo " Solidtime: https://${SOLIDTIME_DOMAIN}"
fi
if [[ "${APPS_TO_INSTALL}" == *"it-tools"* ]] && [ -n "${IT_TOOLS_DOMAIN}" ]; then
    echo " IT-Tools:  https://${IT_TOOLS_DOMAIN}"
fi
echo "=========================================================="
