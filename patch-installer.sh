#!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status.
set -e

INSTALLER_SCRIPT="$1"
OUT_PATH="$2"
GNUSED_PATH="$3"

if [[ -z "$INSTALLER_SCRIPT" || -z "$OUT_PATH" || -z "$GNUSED_PATH" ]]; then
  echo "Usage: $0 <path_to_installer_script> <nix_out_path> <path_to_gnused>"
  exit 1
fi

echo "Patching installer script: $INSTALLER_SCRIPT"
echo "Nix output path: $OUT_PATH"
echo "Using gnused from: $GNUSED_PATH"

SED_CMD="$GNUSED_PATH/bin/sed"

# 1. Bypass root check
"$SED_CMD" -i 's#if \[ `id | sed -e '"'"'s/(.*//'"'"'` \!=\ "uid=0" \]; then#if false; then#g' "$INSTALLER_SCRIPT"

# 2. Redirect installation paths
"$SED_CMD" -i "s|AC_INSTPREFIX=/opt/cisco/anyconnect|AC_INSTPREFIX=$OUT_PATH/opt/cisco/anyconnect|g" "$INSTALLER_SCRIPT"
"$SED_CMD" -i "s|INSTPREFIX=/opt/cisco/secureclient|INSTPREFIX=$OUT_PATH/opt/cisco/secureclient|g" "$INSTALLER_SCRIPT"
"$SED_CMD" -i "s|ROOTCERTSTORE=/opt/.cisco/certificates/ca|ROOTCERTSTORE=$OUT_PATH/opt/.cisco/certificates/ca|g" "$INSTALLER_SCRIPT"
"$SED_CMD" -i "s|/usr/share/icons/hicolor|$OUT_PATH/share/icons/hicolor|g" "$INSTALLER_SCRIPT"
"$SED_CMD" -i "s|/etc/xdg/menus/applications-merged|$OUT_PATH/etc/xdg/menus/applications-merged|g" "$INSTALLER_SCRIPT"
"$SED_CMD" -i "s|/usr/share/desktop-directories|$OUT_PATH/share/desktop-directories|g" "$INSTALLER_SCRIPT"
"$SED_CMD" -i "s|/usr/share/applications|$OUT_PATH/share/applications|g" "$INSTALLER_SCRIPT"
"$SED_CMD" -i "s|/usr/share/gnome-menus|$OUT_PATH/share/gnome-menus|g" "$INSTALLER_SCRIPT"

# 3. Bypass systemd calls
"$SED_CMD" -i '/systemctl/c\true # Patched by Nix' "$INSTALLER_SCRIPT"
"$SED_CMD" -i '/\${INSTALL} -o root -m 644 \${NEWTEMP}\/\${SYSTEMD_CONF}/c\# Patched by Nix' "$INSTALLER_SCRIPT"
"$SED_CMD" -i '/Error: systemd required./c\true # Patched by Nix' "$INSTALLER_SCRIPT"

# 4. Auto-accept license
"$SED_CMD" -i 's|read LICENSEAGREEMENT|LICENSEAGREEMENT="y"|g' "$INSTALLER_SCRIPT"

# 5. Remove all attempts to set file ownership to root
"$SED_CMD" -i 's/ -o root//g' "$INSTALLER_SCRIPT"

# 6. Disable moving the log file at the end of the script
"$SED_CMD" -i '/mv \/tmp\/\${LOGFNAME}/c\# Patched by Nix' "$INSTALLER_SCRIPT"

# 7. Bypass unnecessary process killing (avoids 'ps: not found' error)
"$SED_CMD" -i '/OURPROCS=`ps -A -o pid,command/c\OURPROCS="" # Patched by Nix' "$INSTALLER_SCRIPT"

# 8. Defer execution of helper binaries by commenting them out.
# This is more robust than replacing the lines.

# Target the specific multi-line acinstallhelper command block and comment it out.
"$SED_CMD" -i '/\${BINDIR}\/acinstallhelper -acpolgen/,/orc=\${OCSP_REVOCATION:-false}/s/^/# /' "$INSTALLER_SCRIPT"

# Target the specific manifesttool_vpn execution line and replace it with a no-op.
"$SED_CMD" -i '/\${BINDIR}\/manifesttool_vpn -i/c\true # Patched by Nix' "$INSTALLER_SCRIPT"

echo "Patching complete."
