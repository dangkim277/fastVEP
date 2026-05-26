#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
export FASTVEP_REFERENCE_DIR="$ROOT/reference"
set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a

TAG="${TAG:-$FASTVEP_REF_RELEASE}"
DOCKERHUB_USER="${DOCKERHUB_USER:?Set DOCKERHUB_USER}"
IMAGE="${DOCKERHUB_USER}/fastvep:${TAG}"

[[ -f "$ROOT/fastvep" ]] || { echo "Missing fastvep binary" >&2; exit 1; }
[[ -f "$GFF3" ]] || { echo "Missing $GFF3" >&2; exit 1; }

docker build --platform "${PLATFORM:-linux/amd64}" -t "fastvep:${TAG}" -t "$IMAGE" "$ROOT"
docker push "$IMAGE"
echo "Published $IMAGE"
