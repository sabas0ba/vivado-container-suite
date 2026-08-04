#!/usr/bin/env bash
# Container entrypoint.
#
#   1. drop from root to the invoking user's uid/gid, so nothing written into
#      /work comes back owned by root
#   2. source the Vivado environment
#   3. bring up the optional services the command asked for (Xvfb, hw_server)
#   4. exec the command
set -euo pipefail

log() { printf 'vcs-container: %s\n' "$*" >&2; }
dbg() { [ "${VCS_LOG_LEVEL:-info}" = "debug" ] && log "$*"; return 0; }
fail() { log "ERROR: $*"; exit 1; }

# --------------------------------------------------------------------------
# 1. privilege drop
# --------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ] && [ -n "${VCS_UID:-}" ] && [ "${VCS_PRIVDROPPED:-0}" != "1" ]; then
  uid="$VCS_UID"; gid="${VCS_GID:-$VCS_UID}"
  if [ "$uid" -ne 0 ]; then
    if ! getent group "$gid" >/dev/null; then
      groupadd --gid "$gid" vcsgroup
    fi
    if ! getent passwd "$uid" >/dev/null; then
      useradd --uid "$uid" --gid "$gid" --no-create-home \
              --home-dir "${HOME:-/home/vivado}" --shell /bin/bash vcsuser
    fi
    # plugdev membership is what makes a passed-through JTAG node openable.
    if getent group plugdev >/dev/null; then
      usermod -aG plugdev "$(getent passwd "$uid" | cut -d: -f1)" || true
    fi
    dbg "dropping privileges to ${uid}:${gid}"
    export VCS_PRIVDROPPED=1
    exec setpriv --reuid="$uid" --regid="$gid" --init-groups --inh-caps=-all \
         -- "$0" "$@"
  fi
fi

export HOME="${HOME:-/home/vivado}"
[ -d "$HOME" ] || fail "HOME ($HOME) does not exist inside the container"
[ -w "$HOME" ] || log "WARNING: $HOME is not writable; Vivado's caches and preferences will not persist"

# --------------------------------------------------------------------------
# 2. Vivado environment
# --------------------------------------------------------------------------
xroot="${VCS_CONTAINER_XILINX_ROOT:-/opt/Xilinx}"
edition="${VCS_VIVADO_EDITION:-${VIVADO_EDITION:-Vivado}}"
version="${VCS_VIVADO_VERSION:-${VIVADO_VERSION:-2025.2}}"
settings="$xroot/$edition/$version/settings64.sh"

if [ -f "$settings" ]; then
  dbg "sourcing $settings"
  # settings64.sh is not written for `set -u`.
  set +u
  # shellcheck source=/dev/null
  . "$settings"
  set -u
  export VCS_VIVADO_READY=1
else
  export VCS_VIVADO_READY=0
  if [ "${VCS_REQUIRE_VIVADO:-1}" = "1" ] && [ "${VCS_VIVADO_MODE:-mount}" != "none" ]; then
    log "WARNING: $settings not found -- Vivado is not on PATH."
    log "         mount mode: check VCS_XILINX_ROOT and VCS_VIVADO_VERSION on the host"
    log "         image mode: rebuild with 'vcs build --installer <tarball>'"
  fi
fi

# Keep Vivado's scratch files inside the container, not on the bind mount.
export XILINX_LOCAL_USER_DATA="${XILINX_LOCAL_USER_DATA:-no}"
mkdir -p "$HOME/.Xilinx" 2>/dev/null || true

# Where the flows write.  Vivado will not create a log directory for itself.
if [ -n "${VCS_BUILD_DIR:-}" ] && [ -w /work ]; then
  mkdir -p "/work/${VCS_BUILD_DIR}/logs" 2>/dev/null || true
fi

# --------------------------------------------------------------------------
# 3. optional services
# --------------------------------------------------------------------------
_shutdown_pids=()
cleanup() {
  local p
  for p in "${_shutdown_pids[@]:-}"; do
    if [ -n "$p" ]; then kill "$p" 2>/dev/null || true; fi
  done
}
trap cleanup EXIT INT TERM

if [ "${VCS_DISPLAY_MODE:-none}" = "xvfb" ]; then
  display_num=99
  while [ -e "/tmp/.X11-unix/X${display_num}" ] && [ "$display_num" -lt 120 ]; do
    display_num=$((display_num + 1))
  done
  dbg "starting Xvfb on :${display_num}"
  Xvfb ":${display_num}" -screen 0 "${VCS_XVFB_GEOMETRY:-1920x1080x24}" -nolisten tcp >/dev/null 2>&1 &
  _shutdown_pids+=("$!")
  export DISPLAY=":${display_num}"
  for _ in $(seq 1 50); do
    [ -e "/tmp/.X11-unix/X${display_num}" ] && break
    sleep 0.1
  done
  [ -e "/tmp/.X11-unix/X${display_num}" ] || fail "Xvfb failed to start on :${display_num}"
fi

if [ "${VCS_START_HW_SERVER:-0}" = "1" ] && [ "${1:-}" != "hw_server" ]; then
  if command -v hw_server >/dev/null 2>&1; then
    port="${VCS_HW_SERVER_PORT:-3121}"
    dbg "starting hw_server on TCP::${port}"
    hw_server -s "TCP::${port}" -d >/dev/null 2>&1 &
    _shutdown_pids+=("$!")
    for _ in $(seq 1 100); do
      if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then break; fi
      sleep 0.1
    done
  else
    log "WARNING: VCS_START_HW_SERVER=1 but hw_server is not on PATH"
  fi
fi

# --------------------------------------------------------------------------
# 4. run
# --------------------------------------------------------------------------
if [ $# -eq 0 ]; then set -- bash -l; fi
dbg "exec $*"
exec "$@"
