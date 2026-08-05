# shellcheck shell=bash
# vcs gui -- the Vivado IDE.

cmd_gui() {
  local target=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --vnc)       VCS_VNC=1; shift ;;
      --vnc-port)  VCS_VNC_PORT="${2:?--vnc-port needs a number}"; VCS_VNC=1; shift 2 ;;
      --vnc-bind)  VCS_VNC_BIND="${2:?--vnc-bind needs an address}"; VCS_VNC=1; shift 2 ;;
      -h|--help)
        cat <<'H'
vcs gui [XPR|DCP]

  Launches the Vivado IDE.  With no argument it opens VCS_XPR if set, otherwise
  an empty IDE.  A checkpoint (.dcp) from the non-project flow can be opened
  directly, which is the usual way to inspect a placed & routed design.

  Display transport is chosen by --display / VCS_DISPLAY_MODE:
    auto     X11 if DISPLAY is set, else headless Xvfb  (default)
    x11      X socket, or an ssh-forwarded TCP display, plus a per-run
             untrusted xauth cookie
    wayland  through the compositor's XWayland socket
    xvfb     headless X server inside the container

  --vnc              Export the headless display over VNC.  Implies --display
                     xvfb.  A one-off password is generated and printed unless
                     VCS_VNC_PASSWORD is set; it reaches the container through a
                     mounted file, never an environment variable or an argv.
  --vnc-port N       Host port to publish (default 5901)
  --vnc-bind ADDR    Address to publish on (default 127.0.0.1 -- loopback only)

See docs/06-gui-and-tcl.md.
H
        return 0 ;;
      *) target="$1"; shift ;;
    esac
  done

  [ -z "$target" ] && target="$VCS_XPR"
  export VCS_VNC VCS_VNC_PORT VCS_VNC_BIND

  # VNC exports a headless server, so it selects the display mode itself.
  if [ "$VCS_VNC" -eq 1 ] && [ "$VCS_DISPLAY_MODE" != "xvfb" ]; then
    case "$VCS_DISPLAY_MODE" in
      auto|none) ;;
      *) log_warn "--vnc overrides --display $VCS_DISPLAY_MODE with xvfb" ;;
    esac
    VCS_DISPLAY_MODE=xvfb
  fi

  local mode; mode="$(display_effective_mode)"
  if [ "$mode" = "none" ]; then
    die "no display available.
  Use --display x11 with X forwarding, or --display xvfb for a headless X server
  (then attach with your own VNC/x11vnc), or use 'vcs tcl' for a console."
  fi
  log_info "gui: $(display_describe)"

  local -a argv=(vivado -nojournal -nolog)
  if [ -n "$target" ]; then
    local host_t="$VCS_PROJECT_ROOT/$target"
    case "$target" in /*) host_t="$target" ;; esac
    host_t="$(abspath "$host_t")"
    case "$host_t" in
      "$VCS_PROJECT_ROOT"/*) ;;
      *) die "$target is outside the project root and not visible in the container" ;;
    esac
    argv+=(-source "$VCS_CONTAINER_TCL/open.tcl" -tclargs "$VCS_CONTAINER_WORK/${host_t#"$VCS_PROJECT_ROOT"/}")
  fi

  exec_in_container 1 "${argv[@]}"
}
