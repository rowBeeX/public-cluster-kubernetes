#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

command -v kubectl >/dev/null 2>&1 || {
  printf 'kubectl is required for kustomize rendering\n' >&2
  exit 1
}

failed=0
for overlay in apps/*/overlays/dev; do
  printf 'render %s\n' "$overlay"
  rendered="$(mktemp)"
  if ! kubectl kustomize "$overlay" >"$rendered"; then
    failed=1
  elif ! kubectl apply --dry-run=client --validate=false -f "$rendered" >/dev/null; then
    failed=1
  fi
  rm -f "$rendered"
done

if rg -n '^\s*image:\s*(?![a-z0-9.-]+/)[^[:space:]]+' --pcre2 apps; then
  printf 'unqualified container image found\n' >&2
  failed=1
fi

bad_images="$(rg -n '^\s*image:' apps | rg -v '@sha256:[0-9a-f]{64}$' || true)"
if [[ -n "$bad_images" ]]; then
  printf '%s\n' "$bad_images"
  printf 'container image without immutable sha256 digest found\n' >&2
  failed=1
fi

if rg -n --glob '!*.md' --glob '!scripts/validate.sh' \
  '(password|token|secret)[[:space:]]*:[[:space:]]*[^{$<[:space:]]' apps; then
  printf 'possible cleartext secret marker found\n' >&2
  failed=1
fi

exit "$failed"
