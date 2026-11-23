#!/usr/bin/env bash
# Get a connected iPhone usable on this Linux box, then show its app inventory.
#
# Usage:
#   scripts/usb.sh daemon     (re)start usbmuxd — needs sudo, run it yourself
#   scripts/usb.sh watch      wait until a device is paired & visible
#   scripts/usb.sh apps       dump the installed-app list (name, bundle id, ver, size)
#   scripts/usb.sh install    sideload dist/AppCatcher.ipa over USB
#   scripts/usb.sh pair       (re)pair / trust the phone
#   scripts/usb.sh info       device summary
set -euo pipefail
cd "$(dirname "$0")/.."

cmd="${1:-watch}"
shift || true

case "$cmd" in
  daemon)
    if ! pgrep -x usbmuxd >/dev/null; then
      echo "==> Starting usbmuxd (requires root):"
      echo "    sudo /usr/local/sbin/usbmuxd"
      echo "    (you must run it — this shell has no password-less sudo)"
      exit 2
    fi
    ls -la /var/run/usbmuxd
    ;;
  watch)
    for i in $(seq 1 60); do
      id=$(idevice_id -l 2>/dev/null | head -1 || true)
      if [[ -n "$id" ]]; then
        echo "device seen: $id"
        ideviceinfo -k ProductVersion 2>/dev/null | sed 's/^/    iOS /' || true
        exit 0
      fi
      sleep 2
    done
    echo "no device after 2 minutes. Is the cable a data cable? Unlocked? Trust prompt accepted?" >&2
    exit 1
    ;;
  pair)
    UDID=$(idevice_id -l | head -1 || true)
    [[ -n "$UDID" ]] || { echo "no device"; exit 1; }
    idevicepair pair -u "$UDID"
    ;;
  apps)
    UDID=$(idevice_id -l | head -1 || true)
    [[ -n "$UDID" ]] || { echo "no device"; exit 1; }
    pyio_list() { UDID="$UDID" python3 - "$@" <<'PY'
import json, os, sys, time
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.installation_proxy import InstallationProxyService
udid = os.environ.get("UDID")
ld = create_using_usbmux(serial=udid)
if not ld.paired:
    print("NOT PAIRED — accept the Trust prompt on the phone"); sys.exit(0)
svc = InstallationProxyService(ld)
for attempt in range(3):
    try:
        apps = svc.get_apps(application_type="User", calculate_sizes=True)
        break
    except Exception:
        time.sleep(2)
        apps = None
if not apps:
    print("no apps returned"); sys.exit(1)
out = []
for b, a in apps.items():
    out.append(dict(
        bundle=b,
        name=a.get("CFBundleDisplayName") or a.get("CFBundleName") or b,
        version=a.get("CFBundleShortVersionString") or a.get("CFBundleVersion") or "",
        minos=a.get("MinimumOSVersion") or "",
        static=a.get("StaticDiskUsage") or 0,
        dynamic=a.get("DynamicDiskUsage") or 0,
    ))
print(json.dumps(out, indent=1))
PY
    }
    pyio_list
    ;;
  install)
    UDID=$(idevice_id -l | head -1 || true)
    [[ -n "$UDID" ]] || { echo "no device"; exit 1; }
    [[ -f dist/AppCatcher.ipa ]] || { echo "missing dist/AppCatcher.ipa"; exit 1; }
    python3 - "$UDID" <<'PY'
import sys
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.installation_proxy import InstallationProxyService
udid = sys.argv[1]
ld = create_using_usbmux(serial=udid)
if not ld.paired:
    print("NOT PAIRED — accept the Trust prompt on the phone"); sys.exit(1)
svc = InstallationProxyService(ld)
svc.install("dist/AppCatcher.ipa")
print("installed OK")
PY
    ;;
  info)
    UDID=$(idevice_id -l | head -1 || true)
    [[ -n "$UDID" ]] || { echo "no device"; exit 1; }
    ideviceinfo -u "$UDID" 2>/dev/null | grep -iE 'ProductName|ProductVersion|ProductType|DeviceName|UniqueDeviceID|SerialNumber' | head -12
    echo
    echo "ult " || true
    idevicepair list 2>/dev/null | head -3 || true
    ;;
  *)
    echo "usage: $0 daemon|watch|pair|apps|install|info" >&2
    exit 2
    ;;
esac