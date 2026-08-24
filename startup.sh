#!/usr/bin/env bash
set -Eeuo pipefail

# launchd gives LaunchAgents a minimal PATH. Keep the startup path explicit so
# Homebrew-installed tools are available even before a terminal is opened.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

# This script is also safe to run by hand. The LaunchAgent supplies the same
# wrapper, but direct invocations get the sleep assertion too.
if [[ "${DOTFILES_STARTUP_CAFFEINATED:-0}" != 1 ]]; then
  exec /usr/bin/caffeinate -s /usr/bin/env \
    DOTFILES_STARTUP_CAFFEINATED=1 /bin/bash "$0" "$@"
fi

# Start the local report server, AMP, and keep the Mac awake for as long as
# both services are alive. The LaunchAgent owns this process tree; do not
# orphan the children with nohup/backgrounding and then exit.
TAILSCALE_DIR="${TAILSCALE_DIR:-$HOME/tailscale}"
AMP_DIR="${AMP_DIR:-$HOME/src}"
REPORT_LOG="${SNOWFLAKE_REPORT_LOG:-/tmp/snowflake-report.log}"
AMP_LOG="${AMP_LOG:-/tmp/amp-no-tui.log}"
REPORT_PORT="${SNOWFLAKE_REPORT_PORT:-8080}"
REPORT_BIND="${SNOWFLAKE_REPORT_BIND:-127.0.0.1}"
RUNTIME_DIR="${TMPDIR:-/tmp}"
HTTP_PIDFILE="$RUNTIME_DIR/dotfiles-snowflake-http.pid"
AMP_PIDFILE="$RUNTIME_DIR/dotfiles-amp.pid"
LOCK_DIR="$RUNTIME_DIR/dotfiles-startup.lock"

log() {
  printf 'Startup: %s\n' "$*" >&2
}

if ! mkdir -- "$LOCK_DIR" 2>/dev/null; then
  log "already running; exiting"
  exit 0
fi

http_pid=''
amp_pid=''

cleanup() {
  local pid

  for pid in "$http_pid" "$amp_pid"; do
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done

  for pid in "$http_pid" "$amp_pid"; do
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      wait "$pid" 2>/dev/null || true
    fi
  done

  rm -f -- "$HTTP_PIDFILE" "$AMP_PIDFILE"
  rmdir -- "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 143' INT TERM

find_command() {
  local name="$1"
  local candidate

  candidate="$(command -v "$name" 2>/dev/null || true)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  for candidate in \
    "/opt/homebrew/bin/$name" \
    "/usr/local/bin/$name" \
    "$HOME/.local/bin/$name"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

start_ghostty() {
  local open_bin
  open_bin="$(find_command open)" || {
    log "open command not found"
    return 1
  }

  "$open_bin" -a Ghostty || {
    log "could not launch Ghostty"
    return 1
  }
}

start_report_server() {
  local python_bin
  [[ -d "$TAILSCALE_DIR" ]] || {
    log "report directory not found: $TAILSCALE_DIR"
    return 1
  }

  python_bin="$(find_command python3)" || {
    log "python3 not found"
    return 1
  }

  mkdir -p -- "$(dirname -- "$REPORT_LOG")"
  (
    cd -- "$TAILSCALE_DIR"
    exec "$python_bin" -m http.server "$REPORT_PORT" --bind "$REPORT_BIND"
  ) >"$REPORT_LOG" 2>&1 &
  http_pid=$!
  printf '%s\n' "$http_pid" >"$HTTP_PIDFILE"
}

start_amp() {
  local amp_bin
  [[ -d "$AMP_DIR" ]] || {
    log "AMP directory not found: $AMP_DIR"
    return 1
  }

  amp_bin="$(find_command amp)" || {
    log "amp not found; expected it on PATH or in /opt/homebrew/bin"
    return 1
  }

  mkdir -p -- "$(dirname -- "$AMP_LOG")"
  (
    cd -- "$AMP_DIR"
    exec "$amp_bin" --no-tui
  ) >"$AMP_LOG" 2>&1 &
  amp_pid=$!
  printf '%s\n' "$amp_pid" >"$AMP_PIDFILE"
}

service_is_alive() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

start_ghostty
start_report_server
start_amp

log "Ghostty launched; report server and amp --no-tui are running under caffeinate"

# macOS's system Bash does not have wait -n. Poll both children so a failed
# service tears down the other one and lets launchd restart the job.
while service_is_alive "$http_pid" && service_is_alive "$amp_pid"; do
  sleep 5
done

if ! service_is_alive "$http_pid"; then
  log "report server exited"
else
  log "amp --no-tui exited"
fi
exit 1
