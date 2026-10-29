#!/system/bin/sh
# Root-side WebUI helper. Accepts base64-encoded UTF-8 to avoid shell injection.
set -u
DATA_DIR=${SHM_DATA_DIR:-/data/adb/susfs4ksu-lkm-hide-mounts-by-mask}
MOD_DIR=${SHM_MOD_DIR:-/data/adb/modules/susfs4ksu-lkm-hide-mounts-by-mask}
CONFIG=$DATA_DIR/rules.conf
CTL=${SHM_CTL:-/proc/susfs_hide_mounts}

fail() { printf 'ERROR: %s\n' "$1"; exit 1; }

case "${1:-}" in
  read)
    [ -r "$CONFIG" ] || fail 'Config is missing'
    cat "$CONFIG"
    ;;
  save)
    B64=${2:-}
    [ -n "$B64" ] || fail 'Empty payload'
    [ "${#B64}" -le 32768 ] || fail 'Config exceeds maximum size'
    case "$B64" in *[!A-Za-z0-9+/=]* ) fail 'Invalid base64 characters' ;; esac
    umask 077
    mkdir -p "$DATA_DIR" || fail 'Cannot create data directory'
    TEMP=$(mktemp "$DATA_DIR/.rules.XXXXXX") || fail 'Cannot create temporary file'
    if ! printf '%s' "$B64" | base64 -d > "$TEMP" 2>/dev/null; then
      rm -f "$TEMP"
      fail 'Cannot decode config'
    fi
    if ! sh "$MOD_DIR/bin/validate.sh" "$TEMP"; then
      rm -f "$TEMP"
      fail 'Invalid rule syntax'
    fi
    [ -s "$TEMP" ] || { rm -f "$TEMP"; fail 'Empty config'; }
    if [ -f "$CONFIG" ]; then
      cp -p "$CONFIG" "$DATA_DIR/rules.conf.bak" || { rm -f "$TEMP"; fail 'Cannot back up config'; }
    fi
    chmod 600 "$TEMP" || { rm -f "$TEMP"; fail 'Cannot chmod config'; }
    mv -f "$TEMP" "$CONFIG" || fail 'Cannot save config'
    echo 'OK: configuration saved'
    ;;
  scan)
    [ -r "$CTL" ] || fail 'SUSFS4KSU-for-LKM / susfs_guard_lkm control endpoint not available'
    # Preserve the actual reason (e.g. a full prefix table) for WebUI.
    if scan_result=$(sh "$MOD_DIR/bin/guard.sh" --once 2>&1); then
      echo 'OK: scan completed'
    else
      fail "Scan failed${scan_result:+: $scan_result}"
    fi
    ;;
  status)
    if [ -r "$CTL" ]; then
      cat "$CTL"
    else
      echo 'SUSFS4KSU-for-LKM / susfs_guard_lkm control endpoint not available'
    fi
    ;;
  *) fail 'Use read | save <base64> | scan | status' ;;
esac
