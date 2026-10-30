#!/usr/bin/env bash
# Build the Salesix (sandbox) images for linux/amd64 and push them to GHCR.
# Run on your workstation, NOT on the server.
#
#   cp build.env.example build.env   # fill in SALESIX_SRC + NEXT_PUBLIC_DEMO_API_KEY
#   docker login ghcr.io -u <user>   # token with write:packages
#   ./build-and-push.sh [image ...]  # default: all (backend frontendv2 landing admin demo pitch python-service)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${HERE}/build.env" ] || { echo "Missing ${HERE}/build.env (copy build.env.example)" >&2; exit 1; }
# shellcheck disable=SC1091
set -a; source "${HERE}/build.env"; set +a

: "${SALESIX_SRC:?set SALESIX_SRC in build.env}"
: "${GHCR_NAMESPACE:?set GHCR_NAMESPACE in build.env}"
: "${NEXT_PUBLIC_DEMO_API_KEY:?set NEXT_PUBLIC_DEMO_API_KEY in build.env}"
TAG="${SALESIX_IMAGE_TAG:-latest}"
PLATFORM="${PLATFORM:-linux/amd64}"
API_URL="${API_URL:-https://api.salesix.ai/api}"
FRONTEND_URL="${FRONTEND_URL:-https://app.salesix.ai}"

[ -d "${SALESIX_SRC}/backend" ] || { echo "SALESIX_SRC=${SALESIX_SRC} does not look like the salesix-demo checkout" >&2; exit 1; }
[ -f "${SALESIX_SRC}/frontendv2/.env.production" ] || { echo "frontendv2/.env.production is required at build time (NEXT_PUBLIC_* are baked in)" >&2; exit 1; }

build() { # name context dockerfile [--build-arg ...]
    local name="$1" context="$2" dockerfile="$3"; shift 3
    echo "=== ${name} (${PLATFORM}) -> ${GHCR_NAMESPACE}/salesix-${name}:${TAG}"
    docker buildx build --platform "${PLATFORM}" \
        -f "${SALESIX_SRC}/${context}/${dockerfile}" \
        -t "${GHCR_NAMESPACE}/salesix-${name}:${TAG}" \
        "$@" --push "${SALESIX_SRC}/${context}"
}

build_one() {
    case "$1" in
        backend)        build backend backend Dockerfile ;;
        python-service) build python-service backend/livekit Dockerfile.python-service ;;
        frontendv2)
            # NOTE: frontendv2 copies .env.production (incl. NEXTAUTH_SECRET) into the image: keep the GHCR package private.
            build frontendv2 frontendv2 Dockerfile ;;
        landing)
            build landing landing Dockerfile \
                --build-arg "NEXT_PUBLIC_API_URL=${API_URL}" \
                --build-arg "NEXT_PUBLIC_API_BASE_URL=${API_URL}" \
                --build-arg "NEXT_PUBLIC_DEMO_API_KEY=${NEXT_PUBLIC_DEMO_API_KEY}" \
                --build-arg "NEXT_PUBLIC_GTM_ID=${NEXT_PUBLIC_GTM_ID:-}" \
                --build-arg "NEXT_PUBLIC_GA4_ID=${NEXT_PUBLIC_GA4_ID:-}" \
                --build-arg "NEXT_PUBLIC_META_PIXEL_ID=${NEXT_PUBLIC_META_PIXEL_ID:-}" ;;
        admin)
            build admin admin Dockerfile \
                --build-arg "NEXT_PUBLIC_API_URL=${API_URL}" \
                --build-arg "NEXT_PUBLIC_FRONTEND_URL=${FRONTEND_URL}" ;;
        demo)           build demo demo Dockerfile ;;
        pitch)          build pitch pitch Dockerfile ;;
        *) echo "Unknown image: $1" >&2; exit 1 ;;
    esac
}

IMAGES=("$@")
[ ${#IMAGES[@]} -gt 0 ] || IMAGES=(backend python-service frontendv2 landing admin demo pitch)

# Build one at a time to keep memory use sane
for img in "${IMAGES[@]}"; do build_one "${img}"; done

echo "Done. On the server:  cd apps/salesix && docker compose pull && docker compose up -d"
