# Self-Hosted Apps

A repository for managing docker-compose stacks and configurations for self-hosted applications and services.

## Structure Overview

```text
├── apps/                 # Per-service compose setups and configurations
├── common/               # Shared networks, reverse proxy, or environment definitions
├── .gitignore
└── README.md
```

## Getting Started

1. Create a service folder under `apps/<service-name>`.
2. Add a `docker-compose.yml` and `.env.example` if applicable.
3. Configure environment variables before launching containers.
