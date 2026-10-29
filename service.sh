#!/system/bin/sh
MODDIR=${0%/*}
exec /system/bin/sh "$MODDIR/bin/guard.sh"
