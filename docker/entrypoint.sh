#!/usr/bin/env bash
# Container entrypoint.
#
#   1. drop from root to the invoking user's uid/gid, so nothing written into
#      /work comes back owned by root
#   2. source the Vivado environment
#   3. bring up the optional services the command asked for (Xvfb, hw_server)
#   4. exec the command
set -euo pipefail

log() { printf 'vvd-container: %s\n' "$*" >&2; }
dbg() { [ "${VVD_LOG_LEVEL:-info}" = "debug" ] && log "$*"; return 0; }
fail() { log "ERROR: $*"; exit 1; }

# --------------------------------------------------------------------------
# 1. privilege drop
# --------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ] && [ -n "${VVD_UID:-}" ] && [ "${VVD_PRIVDROPPED:-0}" != "1" ]; then
  uid="$VVD_UID"; gid="${VVD_GID:-$VVD_UID}"
  if [ "$uid" -ne 0 ]; then
    if ! getent group "$gid" >/dev/null; then
      groupadd --gid "$gid" vvdgroup
    fi
    if ! getent passwd "$uid" >/dev/null; then
      useradd --uid "$uid" --gid "$gid" --no-create-home \
              --home-dir "${HOME:-/home/vivado}" --shell /bin/bash vvduser
    fi
    # plugdev membership is what makes a passed-through JTAG node openable.
    if getent group plugdev >/dev/null; then
      usermod -aG plugdev "$(getent passwd "$uid" | cut -d: -f1)" || true
    fi
    dbg "dropping privileges to ${uid}:${gid}"
    export VVD_PRIVDROPPED=1
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
xroot="${VVD_CONTAINER_XILINX_ROOT:-/opt/Xilinx}"
edition="${VVD_VIVADO_EDITION:-${VIVADO_EDITION:-Vivado}}"
version="${VVD_VIVADO_VERSION:-${VIVADO_VERSION:-2025.2}}"
settings="$xroot/$edition/$version/settings64.sh"

if [ -f "$settings" ]; then
  dbg "sourcing $settings"
  # settings64.sh is not written for `set -u`.
  set +u
  # shellcheck source=/dev/null
  . "$settings"
  set -u
  export VVD_VIVADO_READY=1
else
  export VVD_VIVADO_READY=0
  if [ "${VVD_REQUIRE_VIVADO:-1}" = "1" ] && [ "${VVD_VIVADO_MODE:-mount}" != "none" ]; then
    log "WARNING: $settings not found -- Vivado is not on PATH."
    log "         mount mode: check VVD_XILINX_ROOT and VVD_VIVADO_VERSION on the host"
    log "         image mode: rebuild with 'vvd build --installer <tarball>'"
  fi
fi

# Keep Vivado's scratch files inside the container, not on the bind mount.
export XILINX_LOCAL_USER_DATA="${XILINX_LOCAL_USER_DATA:-no}"
mkdir -p "$HOME/.Xilinx" 2>/dev/null || true

# Where the flows write.  Vivado will not create a log directory for itself.
if [ -n "${VVD_BUILD_DIR:-}" ] && [ -w /work ]; then
  mkdir -p "/work/${VVD_BUILD_DIR}/logs" 2>/dev/null || true
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

if [ "${VVD_DISPLAY_MODE:-none}" = "xvfb" ]; then
  display_num=99
  while [ -e "/tmp/.X11-unix/X${display_num}" ] && [ "$display_num" -lt 120 ]; do
    display_num=$((display_num + 1))
  done
  dbg "starting Xvfb on :${display_num}"
  Xvfb ":${display_num}" -screen 0 "${VVD_XVFB_GEOMETRY:-1920x1080x24}" -nolisten tcp >/dev/null 2>&1 &
  _shutdown_pids+=("$!")
  export DISPLAY=":${display_num}"
  for _ in $(seq 1 50); do
    [ -e "/tmp/.X11-unix/X${display_num}" ] && break
    sleep 0.1
  done
  [ -e "/tmp/.X11-unix/X${display_num}" ] || fail "Xvfb failed to start on :${display_num}"

  # Export the headless display so a machine with no X server of its own can
  # still show the GUI.  The password comes from a mounted file, never from the
  # environment or the command line, both of which are readable by anyone who
  # can inspect the container.
  if [ "${VVD_VNC:-0}" = "1" ]; then
    command -v x11vnc >/dev/null 2>&1 ||
      fail "VVD_VNC=1 but x11vnc is not in the image; rebuild with 'vvd build'"
    [ -s /opt/vvd/vnc-password ] ||
      fail "VVD_VNC=1 but /opt/vvd/vnc-password is missing or empty"
    dbg "starting x11vnc on $DISPLAY"
    x11vnc -display "$DISPLAY" \
           -rfbport 5900 \
           -passwdfile /opt/vvd/vnc-password \
           -forever -shared -noxdamage -quiet >/dev/null 2>&1 &
    _shutdown_pids+=("$!")
    for _ in $(seq 1 100); do
      if (exec 3<>/dev/tcp/127.0.0.1/5900) 2>/dev/null; then break; fi
      sleep 0.1
    done
    (exec 3<>/dev/tcp/127.0.0.1/5900) 2>/dev/null ||
      fail "x11vnc did not come up on port 5900"
    log "VNC ready on container port 5900"
  fi
fi

if [ "${VVD_START_HW_SERVER:-0}" = "1" ] && [ "${1:-}" != "hw_server" ]; then
  if command -v hw_server >/dev/null 2>&1; then
    port="${VVD_HW_SERVER_PORT:-3121}"
    dbg "starting hw_server on TCP::${port}"
    hw_server -s "TCP::${port}" -d >/dev/null 2>&1 &
    _shutdown_pids+=("$!")
    for _ in $(seq 1 100); do
      if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then break; fi
      sleep 0.1
    done
  else
    log "WARNING: VVD_START_HW_SERVER=1 but hw_server is not on PATH"
  fi
fi

# --------------------------------------------------------------------------
# 4. run
# --------------------------------------------------------------------------
if [ $# -eq 0 ]; then set -- bash -l; fi
dbg "exec $*"
exec "$@"
