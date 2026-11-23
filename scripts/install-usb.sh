#!/usr/bin/env bash
# Install AppCatcher over USB — the route Apple actually documents for a
# development-signed build. No Mac required.
#
#   1. Plug the iPhone into this machine and unlock it.
#   2. Tap "Trust" on the phone.
#   3. On the phone: Settings › Privacy & Security › Developer Mode › On
#      (iOS restarts once). Required to install any dev-signed app on iOS 16+.
#   4. Run this script. It starts usbmuxd if it is not running (needs sudo,
#      one password prompt), waits for the device, installs and launches.
set -euo pipefail

cd "$(dirname "$0")/.."

IPA="dist/AppCatcher.ipa"
# Resolve the signed bundle id from the IPA itself instead of hard-coding it.
BUNDLE=$(unzip -p "$IPA" "Payload/AppCatcher.app/Info.plist" 2>/dev/null | grep -A1 CFBundleIdentifier | grep string | sed 's/.*<string>\(.*\)<\/string>.*/\1/' | head -1)

[[ -f "$IPA" ]] || { echo "missing $IPA — run scripts/build-ipa.sh first" >&2; exit 1; }

if ! pgrep -x usbmuxd >/dev/null 2>&1; then
  echo "==> starting usbmuxd (needs root)"
  sudo /usr/local/sbin/usbmuxd --user usbmux &>/tmp/usbmuxd.log &
  sleep 2
fi

echo "==> waiting for the iPhone"
for _ in $(seq 1 30); do
  UDID=$(idevice_id -n 2>/dev/null | head -1 || true)
  [[ -n "$UDID" ]] && break
  sleep 1
done
[[ -n "${UDID:-}" ]] || {
  echo "no device seen. Check the cable (data, not charge-only), unlock the phone" >&2
  echo "and tap Trust. Then: sudo usbmuxd; idevice_id -ln" >&2
  exit 1
}
ideviceinfo -k ProductVersion 2>/dev/null | sed 's/^/    iOS /'

echo "==> installing $IPA"
if command -v xtool >/dev/null; then
  xtool install --usb --udid "$UDID" "$IPA"
else
  pymobiledevice3 apps install --developer "$IPA"
fi

echo "==> launching"
xtool launch --udid "$UDID" 2>/dev/null || \
  pymobiledevice3 apps launch "$BUNDLE" 2>/dev/null || \
  echo "    open it by hand — install succeeded"

cat <<DONE

Installed on $UDID. If the icon appears and quits instantly, Developer Mode is
off, or the profile expired; re-run scripts/build-ipa.sh for a fresh profile.
DONE
