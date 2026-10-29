#!/system/bin/sh
# Manual KernelSU Next module action: scan and print the current mount-hiding state.
MODDIR=${0%/*}
CTL=${SHM_CTL:-/proc/susfs_hide_mounts}

printf '%s\n' 'SUSFS4KSU-for-LKM / susfs_guard_lkm' 'Hide mounts by mask' ''

if [ ! -r "$CTL" ] || [ ! -w "$CTL" ]; then
    printf 'ERROR: mount-hiding control endpoint unavailable: %s\n' "$CTL" >&2
    exit 1
fi

# Snapshot registered prefixes before the scan. The control interface is shared
# with other modules, so report changes but never remove or reset anything.
before=$(sed -n 's/^prefixes:[[:space:]]*//p' "$CTL" | head -n 1)

printf 'Scanning mountinfo...\n'
if scan_output=$(/system/bin/sh "$MODDIR/bin/guard.sh" --once 2>&1); then
    result=0
else
    result=$?
fi

if [ -n "$scan_output" ]; then
    printf '%s\n' "$scan_output"
fi

if [ -r "$CTL" ]; then
    after=$(sed -n 's/^prefixes:[[:space:]]*//p' "$CTL" | head -n 1)
    new_prefixes=$(printf '%s\n' "$after" | awk -v old="$before" '
        BEGIN {
            n = split(old, a, /[[:space:]]+/)
            for (i = 1; i <= n; i++) if (a[i] != "") seen[a[i]] = 1
        }
        {
            for (i = 1; i <= NF; i++)
                if (!seen[$i]) print $i
        }
    ')
    new_count=$(printf '%s\n' "$new_prefixes" | awk 'NF { count++ } END { print count+0 }')
    printf '\nNewly registered prefixes: %s\n' "$new_count"
    if [ "$new_count" -gt 0 ]; then
        printf '%s\n' "$new_prefixes"
    elif [ "$result" -eq 0 ]; then
        printf 'All matching mounts are already registered.\n'
    fi
    printf '\nMount hiding status:\n'
    cat "$CTL"
fi

if [ "$result" -eq 0 ]; then
    printf '\nScan completed successfully.\n'
else
    printf '\nERROR: scan failed (exit code %s).\n' "$result" >&2
fi
exit "$result"
