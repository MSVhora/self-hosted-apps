# Self-Hosted Apps

A repository for managing Docker Compose stacks, Nginx reverse proxy configurations, and automated bootstrap scripts for self-hosted applications and services.

## Structure Overview

```text
├── apps/
│   ├── it-tools/             # IT-Tools web utility suite (Text diff, hashes, converters, etc.)
│   └── solidtime/            # Solidtime open-source time tracking stack
├── scripts/
│   ├── bootstrap-server.sh   # Full server bootstrap & interactive/flag-based app installer
│   ├── install-core-stack.sh # Installs Docker, Nginx, Certbot, and UFW
│   ├── setup-swap.sh         # Allocates and tunes 8GB swap memory
│   ├── setup-nginx-domain.sh # Configures Nginx reverse proxy block & Let's Encrypt SSL
│   ├── setup-solidtime.sh    # Automated Solidtime deployer
│   └── setup-it-tools.sh     # Automated IT-Tools deployer
├── .gitignore
└── README.md
```

## Quick Server Bootstrap

Run the bootstrap script as root on a fresh Ubuntu server:

```bash
sudo ./scripts/bootstrap-server.sh
```

### Scripted / Non-Interactive Flags

You can also specify apps and domains directly via CLI arguments:

```bash
# Install everything
sudo ./scripts/bootstrap-server.sh \
  --apps all \
  --solidtime-domain time.picmix.in \
  --it-tools-domain tools.picmix.in \
  --email your-email@example.com

# Install only IT-Tools
sudo ./scripts/bootstrap-server.sh \
  --apps it-tools \
  --it-tools-domain tools.picmix.in \
  --email your-email@example.com
```

---

## Standalone App Setups

### Deploy IT-Tools
```bash
sudo ./scripts/setup-it-tools.sh tools.yourdomain.com your-email@example.com
```

### Deploy Solidtime
```bash
sudo ./scripts/setup-solidtime.sh time.yourdomain.com your-email@example.com
```

### Configure Nginx & SSL for Any Service
```bash
sudo ./scripts/setup-nginx-domain.sh <domain> <upstream_port> [certbot_email]
```
