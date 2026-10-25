#!/usr/bin/env bash
set -euo pipefail

# Build the frontend Docker image and tag it with the last commit hash.
#
# Usage:
#   scripts/build-image.sh              # build with last commit short hash
#   scripts/build-image.sh v1.2.3       # build with explicit tag
#
# Env:
#   IMAGE_PREFIX  Docker registry/user prefix (default: your-org)
#   IMAGE_NAME    Image name (default: cardano-dapp-frontend)
#   PUSH          Set to "true" to push to registry after build (default: false)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TAG="${1:-}"
if [[ -z "${TAG}" ]]; then
  TAG="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
fi

IMAGE_PREFIX="${IMAGE_PREFIX:-your-org}"
IMAGE_NAME="${IMAGE_NAME:-cardano-dapp-frontend}"
PUSH="${PUSH:-false}"

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64) NATIVE_PLATFORM="linux/amd64" ;;
  arm64|aarch64) NATIVE_PLATFORM="linux/arm64" ;;
  *) echo "Unsupported host arch: ${ARCH}" >&2; exit 1 ;;
esac

if [[ "${PUSH}" == "true" ]]; then
  BUILDX_FLAGS=(--platform "${NATIVE_PLATFORM}" --push)
  echo "Push mode: building for ${NATIVE_PLATFORM} and pushing to registry"
else
  BUILDX_FLAGS=(--platform "${NATIVE_PLATFORM}" --load)
  echo "Local mode: building for ${NATIVE_PLATFORM} and loading locally"
fi

cd "${ROOT_DIR}"

IMAGE="${IMAGE_PREFIX}/${IMAGE_NAME}:${TAG}"
echo "Building image: ${IMAGE}"
docker buildx build \
  "${BUILDX_FLAGS[@]}" \
  -f Dockerfile \
  -t "${IMAGE}" \
  .
echo "Built image: ${IMAGE}"
