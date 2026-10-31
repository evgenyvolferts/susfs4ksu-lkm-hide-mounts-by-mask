# SUSFS4KSU-for-LKM Hide Mounts by Mask

[Русский](README.ru.md)

A companion **KernelSU Next module** for **[SUSFS4KSU-for-LKM](https://github.com/inforcqb/susfs4ksu-for-lkm)**. It matches entries in `/proc/self/mountinfo` against configurable path masks and registers the matching **mount targets** for hiding through `/proc/susfs_hide_mounts`.

This helper is intended for the **loadable-kernel-module (LKM)** implementation of SUSFS. When SUSFS is integrated into the kernel and the mounts are already hidden correctly, the helper is usually unnecessary. It does not install or load an LKM.

## Requirements

- **KernelSU Next v3.4.2 build 33442-6 or newer** (minimum supported version).
- **SUSFS4KSU-for-LKM**, with the operational `/proc/susfs_hide_mounts` control interface.

## Purpose and operation

Some bind mounts may remain visible in `mountinfo` with the LKM implementation, even when the built-in SUSFS mount-hiding and KernelSU `try_umount` settings are enabled. For example:

```text
/adb/modules/zygisk_vector/bin/dex2oat64 -> /apex/com.android.art/bin/dex2oat64
/adb/rvhc/youtube-morphe-jhc.apk         -> /data/app/.../base.apk
/adb/rvhc/empty                          -> /product/app/YouTube
```

The `/adb/...` path in these records is the `mountinfo` **root** (column 4), not the mount target (column 5). A prefix `/adb/` in `/proc/susfs_hide_mounts` does not select these records by their root field. This module instead matches the `mountinfo` fields according to the configuration, extracts the **actual target**, and registers that target via the SUSFS4KSU-for-LKM mount-hiding interface. The example configuration also includes the temporary AdGuard Certificate `tmpfs` mount.

The mount-hiding interface is provided by **SUSFS4KSU-for-LKM**, specifically its **`susfs_guard_lkm`** mechanism. This helper does not install that component.

The module **filters mount visibility; it does not unmount anything**. It does not modify the scripts or files belonging to SUSFS4KSU, Zygisk Vector, YouTube Morphe, or AdGuard Certificate.

## WebUI and configuration

The module's **WebUI** is available in KernelSU Next Manager. The interface follows the system light/dark appearance and uses the Manager's Material You colors when available. The offline editor provides **Reload**, **Save**, **Save & scan**, **Scan now**, and **Refresh** actions.

The KernelSU Next module ID is `susfs4ksu-lkm-hide-mounts-by-mask`. The editable configuration is stored separately from the module at:

```text
/data/adb/susfs4ksu-lkm-hide-mounts-by-mask/rules.conf
```

On first installation it is initialized from [`rules.example.conf`](rules.example.conf). Updates retain the user's configuration. Saving validates the syntax, replaces the file atomically, and keeps a `rules.conf.bak` backup.

## Mask syntax

Each non-comment line contains `FIELD|GLOB|FSTYPE`:

```ini
# FIELD|GLOB|FSTYPE
root|/adb/*|*
target|/data/local/tmp/adg-ca-copy|tmpfs
```

- `root` matches column 4 of `mountinfo`; `target` matches column 5.
- `GLOB` matches the complete path, with `*` and `?` wildcards. Bracket expressions, spaces, and backslashes are unsupported.
- `FSTYPE` matches the filesystem type after ` - `, or `*` for any type.
- Empty lines and lines beginning with `#` (including indented comments) are ignored.
- A match registers the **mount target**, not the root. Mount targets containing kernel-escaped characters are skipped.

Masks should be scoped carefully to avoid hiding unrelated mounts.

### Removing rules

**Adding or scanning applies new targets immediately; removing a mask from the configuration does not undo previously registered targets during the current boot.** Removals are applied on the next reboot: the LKM starts with a fresh runtime rule table, and this module registers only targets matching the current configuration. Other components may still independently register the same targets.

Although `/proc/susfs_hide_mounts` supports `del`, its rule list is shared and has no per-module ownership information. This module intentionally does **not** automatically issue `del`, `set`, `reset`, or `clear`, as those operations could interfere with rules maintained by another component. A removed mask therefore cannot be assumed to unhide already marked mounts immediately.

## Installation and updates

The release ZIP is installed through **KernelSU Next Manager**. The module is managed, enabled, disabled, updated, and removed using KernelSU Next Manager's standard module controls.

At startup, KernelSU Next runs the module's own `service.sh`; existing SUSFS4KSU scripts are not modified. The **Action** control in the Manager can trigger a manual rescan. Module updates preserve the rules file stored outside the installed module directory.

## Startup and diagnostics

Until the first user unlock (indicated by `sys.user.0.ce_available=true`), the module scans every 10 seconds. It then scans every 2 seconds for approximately 2 minutes and exits. It does not remain a permanent background service. Unlock detection was verified on a Pixel; other devices may behave differently.

Mounts appearing after the scanning period can be processed by the Manager's **Action** control or the WebUI's **Scan now** action.

For root-side diagnostics:

```sh
cat /proc/susfs_hide_mounts
cat /data/adb/susfs4ksu-lkm-hide-mounts-by-mask/guard.log
sh /data/adb/modules/susfs4ksu-lkm-hide-mounts-by-mask/bin/guard.sh --once
```

Mount-hiding does not guarantee passing a root or integrity detector. The original mounts remain present. The module requires a functioning `/proc/susfs_hide_mounts` interface.

## Removal

The module can be disabled or removed through KernelSU Next Manager. The persistent directory `/data/adb/susfs4ksu-lkm-hide-mounts-by-mask/` is retained intentionally to preserve custom rules across reinstalls; it can be deleted separately when no longer needed. Disabling the module does not immediately revoke kernel-side rules that were already registered during the current boot.

## Known issue: `/adb`-backed bind mounts

Starting with **v0.1.1**, the broad `root|/adb/*|*` rule is commented out by default.

When SUSFS mount hiding is enabled, hiding certain bind mounts backed by `/data` may cause inconsistent `/proc/self/mountinfo` entries. In testing, this resulted in the parent `/data` mount entry being omitted while child mount entries remained visible.

This behavior was reproduced with YouTube Morphe and Zygisk Vector bind mounts. It may trigger `Inconsistent Mount` warnings in root detection tools.

The issue can also occur with individual target rules, so replacing the broad rule with narrower rules does not necessarily resolve it.

**Upstream issue:** [SUSFS4KSU-for-LKM #167](https://github.com/inforcqb/susfs4ksu-for-lkm/issues/167)

**For existing installations:**

- Comment out `root|/adb/*|*` in your saved `rules.conf` if the rule is enabled.
- Review any explicit rules matching `/adb`-backed bind mounts.
- Reboot the device after modifying the rules. Removing prefixes at runtime may not immediately clear previously learned mount identities.

Existing user configurations are preserved during module updates. The new default does not automatically disable previously enabled rules.

This limitation affects the underlying SUSFS mount-hiding mechanism. The module itself only discovers matching mounts and registers their target paths through `/proc/susfs_hide_mounts`.