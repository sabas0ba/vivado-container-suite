# shellcheck shell=bash
# GUI plumbing: X11, XWayland, and headless Xvfb.

VCS_XAUTH_FILE=""

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

  if [ -n "${DISPLAY:-}" ] && [ -d /tmp/.X11-unix ]; then
    printf 'x11'
  elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
    log_warn "Wayland session without XWayland; falling back to headless Xvfb"
    printf 'xvfb'
  else
    printf 'none'
  fi
}

# display_prepare <mode> -- runs in the parent shell, because it creates a
# temporary file that has to survive until the container exits and be cleaned
# up afterwards.
display_prepare() {
  [ "$1" = "x11" ] || return 0
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

# display_args <mode> -- engine run arguments, one per line.
display_args() {
  local mode="$1"
  case "$mode" in
    none|xvfb)
      printf -- '--env\nVCS_DISPLAY_MODE=%s\n' "$mode"
      ;;
    x11)
      [ -n "${DISPLAY:-}" ] || die "DISPLAY is unset; cannot forward X11"
      [ -d /tmp/.X11-unix ] || die "/tmp/.X11-unix is missing; cannot forward X11"
      printf -- '--env\nVCS_DISPLAY_MODE=x11\n'
      printf -- '--env\nDISPLAY=%s\n' "$DISPLAY"
      mount_ro /tmp/.X11-unix /tmp/.X11-unix
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

display_describe() {
  local mode; mode="$(display_effective_mode)" || return 1
  case "$mode" in
    x11)  printf 'X11 forwarding via %s' "${DISPLAY:-?}" ;;
    xvfb) printf 'headless (Xvfb inside the container)' ;;
    none) printf 'no display (batch/Tcl only)' ;;
  esac
}
