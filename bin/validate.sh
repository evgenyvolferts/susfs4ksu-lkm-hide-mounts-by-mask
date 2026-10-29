#!/system/bin/sh
# Check syntax, not semantics. Broad patterns can still match unexpected mounts.
[ "$#" -eq 1 ] && [ -r "$1" ] || { echo 'ERROR: missing config' >&2; exit 1; }
awk -F '|' '
  /^[[:space:]]*(#|$)/ { next }
  {
    # Exactly three fields; reject whitespace/escapes and unsupported glob constructs.
    if (NF != 3 || ($1 != "root" && $1 != "target") ||
        $2 !~ /^\// || $2 ~ /[[:space:]\\\[\]]/ ||
        $3 !~ /^([A-Za-z0-9_.+-]+|\*)$/ || length($2) > 512) {
      printf "Invalid rule at line %d\n", NR
      bad = 1
    }
  }
  END { exit bad ? 1 : 0 }
' "$1"
