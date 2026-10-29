#!/system/bin/sh
# Sourced by the built-in KernelSU installer; $MODPATH and set_perm are provided.
DATA_DIR=/data/adb/susfs4ksu-lkm-hide-mounts-by-mask
mkdir -p "$DATA_DIR" || abort "Cannot create $DATA_DIR"
if [ ! -e "$DATA_DIR/rules.conf" ]; then
    cp "$MODPATH/rules.example.conf" "$DATA_DIR/rules.conf" || abort 'Cannot initialize rules.conf'
    ui_print '- Installed default rules.conf'
else
    ui_print '- Preserved existing rules.conf'
fi
chmod 700 "$DATA_DIR"
chmod 600 "$DATA_DIR/rules.conf"
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/bin/guard.sh" 0 0 0755
set_perm "$MODPATH/bin/config.sh" 0 0 0755
set_perm "$MODPATH/bin/validate.sh" 0 0 0755
ui_print '- WebUI editor available in KernelSU Next Manager'
ui_print '- No existing modules or scripts are modified'
