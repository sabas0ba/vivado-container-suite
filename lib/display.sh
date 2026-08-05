# shellcheck shell=bash
# GUI plumbing: X11 over a Unix socket or TCP, XWayland, headless Xvfb, and VNC.

VCS_XAUTH_FILE=""
VCS_VNC_FILE=""

display_effective_mode() {
  case "$VCS_DISPLAY_MODE" in
    x11|xvfb|none) printf '%s' "$VCS_DISPLAY_MODE"; return 0 ;;
    wayland)
      # Vivado ships an X11-only Qt build, so a Wayland session is served
      # through the compositor's XWayland socket rather than natively.
      [ -n "${DISPLAY:-}" ] ||
        die "display mode 'wayland' needs XWayland (DISPLAY is unset); start XWayland or use --display xvfb"
      printf 'x11'; return 0 ;;
    auto) ;;
    *) die "VCS_DISPLAY_MODE must be auto, x11, wayland, xvfb or none (got: $VCS_DISPLAY_MODE)" ;;
  esac

  if [ -n "${DISPLAY:-}" ]; then
    printf 'x11'
  elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
    log_warn "Wayland session without XWayland; falling back to headless Xvfb"
    printf 'xvfb'
  else
    printf 'none'
  fi
}

# display_transport -- how the X server behind $DISPLAY is reached.
#
#   unix        :0, :0.0, unix:0    -- a socket under /tmp/.X11-unix
#   tcp-local   localhost:10.0      -- what `ssh -X` sets up; the server listens
#                                      on the HOST's loopback, which a bridged
#                                      container cannot reach
#   tcp-remote  10.0.0.5:0          -- an X server elsewhere on the network
display_transport() {
  local d="${DISPLAY:-}"
  case "$d" in
    ''|:*|unix:*) printf 'unix'; return 0 ;;
  esac
  local host="${d%%:*}"
  case "$host" in
    ''|unix)                    printf 'unix' ;;
    localhost|127.0.0.1|::1)    printf 'tcp-local' ;;
    *)                          printf 'tcp-remote' ;;
  esac
}

# display_prepare <mode> -- runs in the parent shell, because it creates
# temporary files that must outlive the emitters and be cleaned up afterwards,
# and because reaching an ssh-forwarded X server changes the network mode for
# the whole invocation.
display_prepare() {
  local mode="$1"

  if [ "$mode" = "x11" ] && [ "$(display_transport)" = "tcp-local" ]; then
    # `ssh -X` leaves sshd listening on the host's 127.0.0.1 (X11UseLocalhost
    # defaults to yes), so no gateway address reaches it -- the container has to
    # share the host's network namespace.
    if [ -z "$VCS_NETWORK" ]; then
      log_debug "DISPLAY=$DISPLAY is an ssh-forwarded TCP display; using host networking"
      VCS_NETWORK=host
    elif [ "$VCS_NETWORK" != "host" ]; then
      log_warn "DISPLAY=$DISPLAY needs host networking, but VCS_NETWORK=$VCS_NETWORK is set"
      log_warn "the GUI will not reach the X server; unset VCS_NETWORK or use --display xvfb --vnc"
    fi
    export VCS_NETWORK
  fi

  if [ "${VCS_VNC:-0}" -eq 1 ]; then
    display_prepare_vnc
  fi

  [ "$mode" = "x11" ] || return 0
  have xauth || {
    log_warn "xauth is not installed on the host; relying on the X server's existing access control"
    return 0
  }
  [ -n "${DISPLAY:-}" ] || return 0

  VCS_XAUTH_FILE="$(mktemp -t vcs-xauth.XXXXXX)"
  VCS_TEMP_FILES+=("$VCS_XAUTH_FILE")
  # An untrusted, per-run cookie: narrower than `xhost +local:`, and it is
  # discarded when the command exits.
  if xauth nlist "$DISPLAY" 2>/dev/null | sed -e 's/^..../ffff/' |
       xauth -f "$VCS_XAUTH_FILE" nmerge - 2>/dev/null && [ -s "$VCS_XAUTH_FILE" ]; then
    chmod 0644 "$VCS_XAUTH_FILE"
  else
    rm -f "$VCS_XAUTH_FILE"
    VCS_XAUTH_FILE=""
    log_warn "could not export an X cookie; if the GUI fails to connect, run: xhost +SI:localuser:$(id -un)"
  fi
}

# display_prepare_vnc -- write the VNC password to a file the container reads.
#
# The password is never passed as an environment variable or an argument: both
# are visible to anyone who can run `docker inspect` or `ps` on the host.
display_prepare_vnc() {
  local password="${VCS_VNC_PASSWORD:-}" generated=0
  if [ -z "$password" ]; then
    # Read a fixed amount and filter, rather than piping an endless /dev/urandom
    # into `head`: under `set -o pipefail` the SIGPIPE that kills the producer
    # would take the whole command down with status 141.
    password="$(head -c 24 /dev/urandom | base64 | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-16)"
    [ "${#password}" -ge 12 ] || die "could not generate a VNC password"
    generated=1
  fi

  VCS_VNC_FILE="$(mktemp -t vcs-vnc.XXXXXX)"
  VCS_TEMP_FILES+=("$VCS_VNC_FILE")
  chmod 0600 "$VCS_VNC_FILE"
  printf '%s\n' "$password" >"$VCS_VNC_FILE"

  if [ "$VCS_VNC_BIND" = "0.0.0.0" ]; then
    log_warn "publishing VNC on all interfaces; anyone who can reach port $VCS_VNC_PORT can drive the GUI"
  fi

  log_info "VNC on ${VCS_VNC_BIND}:${VCS_VNC_PORT}"
  if [ "$generated" -eq 1 ]; then
    log_info "password: $password  (one-off; set VCS_VNC_PASSWORD to choose your own)"
  else
    log_info "password: from VCS_VNC_PASSWORD"
  fi
  if [ "$VCS_VNC_BIND" = "127.0.0.1" ]; then
    log_info "from another machine:  ssh -L ${VCS_VNC_PORT}:127.0.0.1:${VCS_VNC_PORT} $(id -un)@$(hostname)"
  fi
}

# display_args <mode> -- engine run arguments, one per line.
display_args() {
  local mode="$1"
  case "$mode" in
    none)
      printf -- '--env\nVCS_DISPLAY_MODE=none\n'
      ;;
    xvfb)
      printf -- '--env\nVCS_DISPLAY_MODE=xvfb\n'
      vnc_args
      ;;
    x11)
      [ -n "${DISPLAY:-}" ] || die "DISPLAY is unset; cannot forward X11"
      printf -- '--env\nVCS_DISPLAY_MODE=x11\n'
      printf -- '--env\nDISPLAY=%s\n' "$DISPLAY"

      case "$(display_transport)" in
        unix)
          [ -d /tmp/.X11-unix ] || die "/tmp/.X11-unix is missing; cannot forward X11"
          mount_ro /tmp/.X11-unix /tmp/.X11-unix ;;
        tcp-local|tcp-remote)
          # A TCP display needs no socket; reachability is a network concern,
          # handled in display_prepare.
          : ;;
      esac

      if [ -n "$VCS_XAUTH_FILE" ]; then
        mount_ro "$VCS_XAUTH_FILE" "$VCS_CONTAINER_HOME/.Xauthority"
        printf -- '--env\nXAUTHORITY=%s/.Xauthority\n' "$VCS_CONTAINER_HOME"
      fi

      # Software rendering is the portable default; --gpu opts into direct
      # rendering when the host has a usable DRI device.
      if [ "${VCS_GPU:-0}" -eq 1 ]; then
        [ -d /dev/dri ] || die "--gpu requested but /dev/dri does not exist"
        printf -- '--device\n/dev/dri\n'
      else
        printf -- '--env\nLIBGL_ALWAYS_SOFTWARE=1\n'
      fi
      ;;
    *) die "internal: unknown display mode '$mode'" ;;
  esac
}

vnc_args() {
  [ "${VCS_VNC:-0}" -eq 1 ] || return 0
  [ -n "$VCS_VNC_FILE" ] || die "internal: display_prepare_vnc did not run"
  printf -- '--env\nVCS_VNC=1\n'
  mount_ro "$VCS_VNC_FILE" /opt/vcs/vnc-password
  if [ "$VCS_NETWORK" = "host" ]; then
    # Published ports are discarded under host networking; the port is already
    # on the host, so say so rather than letting the engine warn cryptically.
    log_warn "host networking is in effect; VNC listens on the host's port 5900 directly, not ${VCS_VNC_PORT}"
  else
    printf -- '--publish\n%s:%s:5900\n' "$VCS_VNC_BIND" "$VCS_VNC_PORT"
  fi
}

display_describe() {
  local mode; mode="$(display_effective_mode)" || return 1
  case "$mode" in
    x11)
      case "$(display_transport)" in
        unix)       printf 'X11 forwarding via %s (socket)' "$DISPLAY" ;;
        tcp-local)  printf 'X11 forwarding via %s (ssh-forwarded; needs host networking)' "$DISPLAY" ;;
        tcp-remote) printf 'X11 forwarding via %s (remote X server)' "$DISPLAY" ;;
      esac ;;
    xvfb)
      if [ "${VCS_VNC:-0}" -eq 1 ]; then
        printf 'headless Xvfb, exported over VNC on %s:%s' "$VCS_VNC_BIND" "$VCS_VNC_PORT"
      else
        printf 'headless (Xvfb inside the container)'
      fi ;;
    none) printf 'no display (batch/Tcl only)' ;;
  esac
}
