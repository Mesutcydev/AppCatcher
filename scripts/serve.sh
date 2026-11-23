#!/usr/bin/env bash
# Start (or restart) the AppCatcher distribution server on the tailnet.
#
#   scripts/serve.sh start|stop|restart|status|logs
#
# The page and the IPA are reachable only from inside the tailnet:
#   https://kareem.taile90653.ts.net/appcatcher/
set -euo pipefail

cd "$(dirname "$0")/.."

PORT="${APPCATCHER_DIST_PORT:-4713}"
PATH_PREFIX="/appcatcher"
HOST="kareem.taile90653.ts.net"
PID_FILE="/tmp/appcatcher-dist.pid"
LOG_FILE="/tmp/appcatcher-dist.log"

stop() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    sleep 1
  fi
  pkill -f "serve-dist.py" 2>/dev/null || true
  rm -f "$PID_FILE"
}

start() {
  setsid nohup python3 scripts/serve-dist.py >"$LOG_FILE" 2>&1 </dev/null &
  echo $! >"$PID_FILE"
  sleep 1.5
  if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "dist server running (pid $(cat "$PID_FILE")) → $LOG_FILE"
  else
    echo "dist server failed to start:" >&2
    tail -20 "$LOG_FILE" >&2
    exit 1
  fi

  # Publish through tailscale. Fails quietly if the path is already mounted.
  tailscale serve --bg --https=443 --set-path "$PATH_PREFIX" "$PORT" >/dev/null 2>&1 || true
  echo "https://$HOST$PATH_PREFIX/"
}

status() {
  local running="stopped"
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    running="running (pid $(cat "$PID_FILE"))"
  fi
  echo "server: $running on :$PORT"
  echo "route:"
  tailscale serve status 2>/dev/null | grep -A1 "$PATH_PREFIX" || echo "  not mounted"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    "https://$HOST$PATH_PREFIX/AppCatcher.ipa" 2>/dev/null || echo "n/a")
  echo "ipa over tailnet: HTTP $code"
}

case "${1:-start}" in
  start)   start ;;
  stop)    stop; echo "stopped"; tailscale serve --https=443 --set-path "$PATH_PREFIX" off >/dev/null 2>&1 || true ;;
  restart) stop; start ;;
  status)  status ;;
  logs)    tail -n 40 "$LOG_FILE" ;;
  *)       echo "usage: $0 start|stop|restart|status|logs" >&2; exit 2 ;;
esac
