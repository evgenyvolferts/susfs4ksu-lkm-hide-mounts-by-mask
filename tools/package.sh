#!/usr/bin/env bash
# Package a KernelSU Next module with files at the archive root.
# Usage: bash tools/package.sh [vMAJOR.MINOR[.PATCH]]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_NAME="susfs4ksu-lkm-hide-mounts-by-mask"
TAG="${1:-}"
VERSION_CODE=""

if [[ -n "$TAG" ]]; then
  if [[ ! "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?$ ]]; then
    echo "Expected release tag vMAJOR.MINOR[.PATCH], got: $TAG" >&2
    exit 1
  fi
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[4]:-0}"
  if (( ${#major} > 4 || ${#minor} > 3 || ${#patch} > 3 )); then
    echo 'Version component exceeds supported range' >&2
    exit 1
  fi
  VERSION_CODE=$((10#$major * 1000000 + 10#$minor * 1000 + 10#$patch))
  if (( 10#$minor >= 1000 || 10#$patch >= 1000 || VERSION_CODE < 1 || VERSION_CODE > 2147483647 )); then
    echo 'Invalid versionCode (must fit positive signed 32-bit integer)' >&2
    exit 1
  fi
fi

OUT_DIR="$ROOT_DIR/dist"
mkdir -p "$OUT_DIR"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

files=(
  module.prop
  LICENSE
  customize.sh
  service.sh
  action.sh
  rules.example.conf
  bin/guard.sh
  bin/config.sh
  bin/validate.sh
  webroot/index.html
  webroot/styles.css
  webroot/app.js
)
for file in "${files[@]}"; do
  mkdir -p "$STAGING/$(dirname "$file")"
  mode=644
  [[ "$file" == *.sh ]] && mode=755
  install -m "$mode" "$ROOT_DIR/$file" "$STAGING/$file"
done

if [[ -n "$TAG" ]]; then
  awk -v tag="$TAG" -v code="$VERSION_CODE" '
    /^version=/ { print "version=" tag; next }
    /^versionCode=/ { print "versionCode=" code; next }
    { print }
  ' "$STAGING/module.prop" > "$STAGING/module.prop.tmp"
  mv "$STAGING/module.prop.tmp" "$STAGING/module.prop"
  chmod 644 "$STAGING/module.prop"
fi

OUT_FILE="$OUT_DIR/$REPO_NAME-${TAG:-dev}.zip"
rm -f "$OUT_FILE"
(
  cd "$STAGING"
  zip -q "$OUT_FILE" "${files[@]}"
)
printf 'Created %s\n' "$OUT_FILE"
