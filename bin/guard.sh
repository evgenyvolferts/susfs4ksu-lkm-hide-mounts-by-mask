#!/system/bin/sh
# SUSFS4KSU-for-LKM / susfs_guard_lkm mount-point registration (no unmounting).
# Configurable paths primarily intended for /proc/self/mountinfo.
# Executed by KernelSU module service.sh; --once for manual inspection.

CTL=${SHM_CTL:-/proc/susfs_hide_mounts}
MI=${SHM_MI:-/proc/self/mountinfo}
CONFIG=${SHM_CONFIG:-/data/adb/susfs4ksu-lkm-hide-mounts-by-mask/rules.conf}
LOG=${SHM_LOG:-/data/adb/susfs4ksu-lkm-hide-mounts-by-mask/guard.log}

log_msg() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

has_rule() {
    awk -v p="$1" '
        $1 == "prefixes:" {
            for (i = 2; i <= NF; i++)
                if ($i == p) found = 1
        }
        END { exit !found }
    ' "$CTL"
}

# Emit the target for each matching entry. The separator ` - ` identifies
# mountinfo's filesystem-type field. Masks use only * and ? wildcards.
match_targets() {
    awk -F ' - ' '
    function glob_re(glob,   i,c,re) {
        re = "^"
        for (i = 1; i <= length(glob); i++) {
            c = substr(glob,i,1)
            if (c == "*") re = re ".*"
            else if (c == "?") re = re "."
            else {
                if (index("\\.^$+()[]{}|",c)) re = re "\\"
                re = re c
            }
        }
        return re "$"
    }
    FNR == NR {
        sub(/\r$/, "")
        if ($0 ~ /^[[:space:]]*(#|$)/) next
        n = split($0, a, /[|]/)
        if (n != 3) next
        if (a[1] != "root" && a[1] != "target") next
        if (a[2] !~ /^\// || a[3] == "") next
        rule_field[++num] = a[1]
        rule_path[num] = glob_re(a[2])
        rule_fs[num] = a[3]
        next
    }
    NF == 2 {
        nleft = split($1,left,/ +/)
        nright = split($2,right,/ +/)
        if (nleft < 5 || nright < 2) next
        root = left[4]
        target = left[5]
        fstype = right[1]
        # Skipping kernel-escaped target paths avoids feeding encoded strings
        # such as \\040 to the /proc control endpoint.
        if (target !~ /^\// || index(target,"\\")) next
        for (i = 1; i <= num; i++) {
            candidate = (rule_field[i] == "root") ? root : target
            if (candidate ~ rule_path[i] &&
                (rule_fs[i] == "*" || rule_fs[i] == fstype)) {
                print target
                break
            }
        }
    }' "$CONFIG" "$MI"
}

is_protected() {
    # Do not accidentally hide essential mountpoints even if a rule is broad.
    case "$1" in
        /|/data|/data/adb|/data/adb/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*)
            return 0 ;;
    esac
    return 1
}

scan_mounts() {
    if [ ! -r "$CTL" ] || [ ! -w "$CTL" ]; then
        printf 'ERROR: mount-hiding control endpoint unavailable: %s\n' "$CTL" >&2
        return 1
    fi
    if [ ! -r "$MI" ] || [ ! -r "$CONFIG" ]; then
        printf 'ERROR: mountinfo or rules configuration is unreadable\n' >&2
        return 1
    fi
    sh "${0%/*}/validate.sh" "$CONFIG" || return 1

    # Avoid a piped while loop: POSIX shells may run it in a subshell, losing
    # the failure counter and causing scan_mounts() to report false success.
    # Keep temporary results alongside the persistent configuration.
    data_dir=${CONFIG%/*}
    candidates=$(mktemp "$data_dir/.mount-candidates.XXXXXX") || {
        printf 'ERROR: cannot create mount scan temporary file\n' >&2
        return 1
    }
    sorted=$(mktemp "$data_dir/.mount-sorted.XXXXXX") || {
        rm -f "$candidates"
        printf 'ERROR: cannot create mount scan temporary file\n' >&2
        return 1
    }

    if ! match_targets > "$candidates" || ! sort -u "$candidates" > "$sorted"; then
        rm -f "$candidates" "$sorted"
        printf 'ERROR: cannot inspect mountinfo or sort mount candidates\n' >&2
        return 1
    fi

    failures=0
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        is_protected "$target" && continue
        has_rule "$target" && continue
        if printf 'add %s\n' "$target" > "$CTL"; then
            log_msg "added $target"
        else
            log_msg "ERROR adding $target"
            printf 'ERROR: could not register mount target %s\n' "$target" >&2
            failures=$((failures + 1))
        fi
    done < "$sorted"
    rm -f "$candidates" "$sorted"

    if [ "$failures" -ne 0 ]; then
        printf 'ERROR: %s mount target(s) were not registered\n' "$failures" >&2
        return 1
    fi
    return 0
}
if [ "$1" = '--once' ]; then
    scan_mounts
    exit $?
fi

# Late mounts (e.g. patched YouTube) may appear after first unlock.
# Before unlock, poll every 10 s; after unlock, scan every 2 s for 2 min.
# Runs only for this boot, not as a permanent daemon.
while [ "$(getprop sys.user.0.ce_available)" != 'true' ]; do
    scan_mounts
    sleep 10
done

i=0
while [ "$i" -lt 60 ]; do
    scan_mounts
    i=$((i + 1))
    sleep 2
done
