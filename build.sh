#!/usr/bin/env bash
# Build & push the velero-plugin-for-alibabacloud multi-arch image.
#
# Usage:
#   ./build.sh <tag>                  # e.g. ./build.sh v1.14.3
#   IMAGE=other/repo ./build.sh v1.14.3
#   PLATFORMS=linux/amd64 ./build.sh v1.14.3

set -euo pipefail

IMAGE="${IMAGE:-guswong/velero-plugin-for-alibabacloud}"
TAG="${1:-${TAG:-}}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

if [[ -z "$TAG" ]]; then
  echo "usage: $0 <tag>    (e.g. $0 v1.14.3)" >&2
  echo "       or: TAG=v1.14.3 $0" >&2
  exit 2
fi

echo "==> $IMAGE:$TAG ($PLATFORMS)"
docker buildx build --platform "$PLATFORMS" \
  -t "$IMAGE:$TAG" \
  --push .
