#!/usr/bin/env bash
# Build, sign and publish the AppCatcher IPA.
#
#   scripts/build-ipa.sh            release build + sign + publish to dist/ and ~/Documents
#   scripts/build-ipa.sh --debug    debug build (faster, still signed)
#   scripts/build-ipa.sh --serve    also (re)start the tailnet download server
set -euo pipefail

cd "$(dirname "$0")/.."

HOST="${APPCATCHER_HOST:-kareem.taile90653.ts.net}"
PATH_PREFIX="/appcatcher"
CONFIG=release
if [[ "${1:-}" == "--debug" ]]; then CONFIG=debug; fi

echo "==> Building ($CONFIG), signing, packaging"
xtool dev build -c "$CONFIG" --sign --ipa

echo "==> Publishing"
mkdir -p dist
cp -f xtool/AppCatcher.ipa dist/AppCatcher.ipa
cp -f dist/AppCatcher.ipa "$HOME/Documents/AppCatcher.ipa"

# Keep the checksum printed on the landing page honest.
SHA=$(sha256sum dist/AppCatcher.ipa | cut -c1-64)
if [[ -f dist/index.html ]]; then
  sed -i "s|<dd>[0-9a-f]\{8\}…[0-9a-f]\{8\}</dd>|<dd>${SHA:0:8}…${SHA: -8}</dd>|" dist/index.html
fi

# Reflect what is actually inside the archive instead of hard-coding it.
BUNDLE=$(python3 - <<'PY'
import re, zipfile
try:
    data = zipfile.ZipFile('dist/AppCatcher.ipa').read('Payload/AppCatcher.app/Info.plist')
    match = re.search(rb'CFBundleIdentifier</key>\s*<string>(.*?)</string>', data)
    print(match.group(1).decode() if match else '')
except Exception:
    print('')
PY
)
if [[ -n "$BUNDLE" ]]; then
  python3 - "$BUNDLE" "$HOST" "$PATH_PREFIX" <<'PY'
import re, sys
bundle, host, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
path = 'dist/manifest.plist'
text = open(path).read()
text = re.sub(r'(<key>bundle-identifier</key>\s*<string>)[^<]*(</string>)', r'\g<1>%s\g<2>' % bundle, text)
text = re.sub(r'(<key>url</key>\s*<string>)[^<]*(</string>)',
              r'\g<1>https://%s%s/AppCatcher.ipa\g<2>' % (host, prefix), text)
open(path, 'w').write(text)
print("manifest -> %s" % bundle)
PY
  cp -f dist/manifest.plist "$HOME/Documents/AppCatcher.manifest.plist"
fi

ls -lh "$HOME/Documents/AppCatcher.ipa"
echo "sha256 $SHA"

if [[ "${1:-}" == "--serve" ]]; then
  echo "==> Publishing over the tailnet"
  scripts/serve.sh restart
fi

cat <<NEXT

Download (tailnet only):
  https://${HOST}${PATH_PREFIX}/
  https://${HOST}${PATH_PREFIX}/AppCatcher.ipa

Install on the paired iPhone:
  xtool devices --usb
  xtool install ~/Documents/AppCatcher.ipa

NEXT
