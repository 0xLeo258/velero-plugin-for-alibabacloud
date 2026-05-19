#!/usr/bin/env bash
# Verify a velero-plugin-for-alibabacloud build contains the malformed-tag
# patches (commits 6df34d2, 6012ea8 on branch HC01-664991).
#
# Accepts any of:
#   - a docker image reference (will be pulled if not cached)
#   - a path to a `docker save` tar archive (.tar)
#   - a path to an extracted plugin binary
#
# Usage: ./hack/verify-image.sh <image-ref | tar-path | binary-path>
# Examples:
#   ./hack/verify-image.sh guswong/velero-plugin-for-alibabacloud:v1.14.1
#   ./hack/verify-image.sh ./image.tar
#   ./hack/verify-image.sh ./velero-plugin-for-alibabacloud-amd64

set -euo pipefail

INPUT="${1:-}"
if [[ -z "$INPUT" ]]; then
  echo "usage: $0 <image-ref | tar-path | binary-path>" >&2
  exit 2
fi

WORKDIR="$(mktemp -d -t velero-verify.XXXXXX)"
CID=""
cleanup() {
  if [[ -n "$CID" ]]; then docker rm -f "$CID" >/dev/null 2>&1 || true; fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# Resolve $INPUT into a binary path at $BIN.
BIN=""
if [[ -f "$INPUT" ]]; then
  case "$INPUT" in
    *.tar|*.tar.gz|*.tgz)
      echo "=== [1/5] loading image from tar: $INPUT ==="
      LOAD_OUT="$(docker load -i "$INPUT")"
      echo "$LOAD_OUT"
      IMAGE="$(printf '%s\n' "$LOAD_OUT" | awk -F': ' '/Loaded image/ {print $2; exit}')"
      if [[ -z "$IMAGE" ]]; then
        echo "could not parse image ref from docker load output" >&2
        exit 1
      fi
      ;;
    *)
      echo "=== [1/5] using local binary: $INPUT ==="
      BIN="$INPUT"
      ;;
  esac
else
  IMAGE="$INPUT"
  echo "=== [1/5] pulling image: $IMAGE ==="
  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker pull "$IMAGE" >/dev/null
  else
    echo "  (already cached locally)"
  fi
fi

# If we have an image (not a direct binary), extract its filesystem.
if [[ -z "$BIN" ]]; then
  echo "=== [2/5] extracting filesystem from $IMAGE ==="
  CID="$(docker create "$IMAGE")"
  docker export "$CID" | tar -x -C "$WORKDIR" 2>/dev/null || true
  BIN="$(find "$WORKDIR" -type f \( -name 'velero-plugin-alibabacloud' -o -name 'velero-plugin-for-alibabacloud' -o -name 'velero-plugin*' \) 2>/dev/null | head -n1 || true)"
  if [[ -z "$BIN" ]]; then
    echo "FAIL: no velero-plugin binary found in image" >&2
    exit 1
  fi
  echo "found binary: ${BIN#$WORKDIR}"
else
  echo "=== [2/5] using binary directly ==="
fi

echo "size: $(wc -c <"$BIN") bytes"
echo "sha256: $(shasum -a 256 "$BIN" | awk '{print $1}')"

PASS=0
FAIL=0

check() {
  local label="$1" status="$2" detail="$3"
  if [[ "$status" == "ok" ]]; then
    echo "  [PASS] $label: $detail"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] $label: $detail"
    FAIL=$((FAIL+1))
  fi
}

echo
echo "=== [3/5] build info (go version -m) ==="
if command -v go >/dev/null 2>&1; then
  if BUILDINFO="$(go version -m "$BIN" 2>/dev/null)"; then
    echo "$BUILDINFO" | sed 's/^/  /'
    REV="$(printf '%s\n' "$BUILDINFO" | awk '/vcs\.revision/ {print $2}')"
    MOD="$(printf '%s\n' "$BUILDINFO" | awk '/vcs\.modified/ {print $2}')"
    if [[ -n "$REV" ]]; then
      check "vcs.revision present" ok "$REV (modified=${MOD:-unknown})"
    else
      check "vcs.revision present" miss "no vcs stamp — built with -buildvcs=false?"
    fi
  else
    check "go version -m" miss "binary not recognized by go toolchain"
  fi
else
  echo "  (go toolchain not found, skipping)"
fi

echo
echo "=== [4/5] symbol check: isInvalidTag ==="
SYMS=""
if command -v go >/dev/null 2>&1; then
  SYMS="$(go tool nm "$BIN" 2>/dev/null || true)"
fi
if [[ -z "$SYMS" ]] && command -v nm >/dev/null 2>&1; then
  SYMS="$(nm "$BIN" 2>/dev/null || true)"
fi

if [[ -z "$SYMS" ]]; then
  check "symbol table" miss "could not read symbols (no go/nm or stripped binary)"
else
  HIT="$(printf '%s\n' "$SYMS" | grep -i 'isInvalidTag' || true)"
  if [[ -n "$HIT" ]]; then
    check "isInvalidTag symbol" ok "found"
    printf '%s\n' "$HIT" | sed 's/^/    /'
  else
    check "isInvalidTag symbol" miss "NOT found — patch 6012ea8 is missing"
  fi
  # Note: const names like systemTagPrefixACS often get inlined and don't
  # survive in the symbol table even when the patch IS present, so we don't
  # check for them — the strings check below catches the literals instead.
fi

echo
echo "=== [5/5] strings sanity check ==="
if command -v strings >/dev/null 2>&1; then
  # Cache strings output to avoid SIGPIPE-vs-pipefail interaction
  # (early grep exit on match would otherwise mark the pipeline failed).
  STRINGS_OUT="$WORKDIR/strings.txt"
  strings "$BIN" >"$STRINGS_OUT"
  # Substring match — these constants are typically embedded in longer
  # blobs, so full-line matching gives false negatives. This is the weakest
  # signal anyway; the symbol check above is the real evidence.
  for s in 'acs:' 'aliyun' 'http://' 'https://'; do
    if grep -Fq "$s" "$STRINGS_OUT"; then
      check "string \"$s\"" ok "present"
    else
      check "string \"$s\"" miss "NOT present"
    fi
  done
else
  echo "  (strings not found, skipping)"
fi

echo
echo "=== summary ==="
echo "  passed: $PASS"
echo "  failed: $FAIL"
echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "VERDICT: binary appears to contain the malformed-tag patches."
  exit 0
else
  echo "VERDICT: one or more checks failed — review above."
  exit 1
fi
