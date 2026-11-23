#!/usr/bin/env python3
"""Static file server for the AppCatcher tailnet distribution page.

Serves ./dist on 127.0.0.1 (tailscale serve proxies the public tailnet
endpoint to it). Two content types matter for over-the-air install:

  manifest.plist  -> text/xml              iOS refuses to parse it otherwise
  *.ipa           -> application/octet-stream

Run through scripts/serve.sh, which keeps it alive in the background.
"""

import functools
import http.server
import os
import socketserver
import sys

PORT = int(os.environ.get("APPCATCHER_DIST_PORT", "4713"))
# Bind all interfaces so the phone can fetch inventory.json straight over the
# LAN (the Tailscale route also funnels through this same server).
BIND = os.environ.get("APPCATCHER_DIST_BIND", "0.0.0.0")
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "dist")

EXTRA_TYPES = {
    ".plist": "text/xml",
    ".ipa": "application/octet-stream",
    ".html": "text/html",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        ext = os.path.splitext(path)[1].lower()
        return EXTRA_TYPES.get(ext) or super().guess_type(path)

    def end_headers(self):
        # Re-downloading a 2.6 MB IPA because of a stale cache helps nobody.
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):
        # `tailscale serve` proxies everything from 127.0.0.1, so the peer
        # address alone cannot tell a phone request from my own curl. The
        # forwarded header and the user agent can.
        client = self.headers.get("X-Forwarded-For") or self.address_string()
        agent = self.headers.get("User-Agent") or "-"
        agent = agent[:70]
        sys.stderr.write("%s [%s] %s\n" % (client, agent, fmt % args))
        sys.stderr.flush()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    if not os.path.isdir(ROOT):
        sys.exit("dist/ missing — run scripts/build-ipa.sh first")
    handler = functools.partial(Handler, directory=ROOT)
    with Server(("127.0.0.1", PORT), handler) as httpd:
        print("serving %s on http://127.0.0.1:%d" % (ROOT, PORT), flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
