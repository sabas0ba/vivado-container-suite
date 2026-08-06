# shellcheck shell=bash
# vvd gui -- the Vivado IDE.

cmd_gui() {
  local target=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --vnc)       VVD_VNC=1; shift ;;
      --vnc-port)  VVD_VNC_PORT="${2:?--vnc-port needs a number}"; VVD_VNC=1; shift 2 ;;
      --vnc-bind)  VVD_VNC_BIND="${2:?--vnc-bind needs an address}"; VVD_VNC=1; shift 2 ;;
      -h|--help)
        cat <<'H'
vvd gui [XPR|DCP]

  Launches the Vivado IDE.  With no argument it opens VVD_XPR if set, otherwise
  an empty IDE.  A checkpoint (.dcp) from the non-project flow can be opened
  directly, which is the usual way to inspect a placed & routed design.

  Display transport is chosen by --display / VVD_DISPLAY_MODE:
    auto     X11 if DISPLAY is set, else headless Xvfb  (default)
    x11      X socket, or an ssh-forwarded TCP display, plus a per-run
             untrusted xauth cookie
    wayland  through the compositor's XWayland socket
    xvfb     headless X server inside the container

  --vnc              Export the headless display over VNC.  Implies --display
                     xvfb.  A one-off password is generated and printed unless
                     VVD_VNC_PASSWORD is set; it reaches the container through a
                     mounted file, never an environment variable or an argv.
  --vnc-port N       Host port to publish (default 5901)
  --vnc-bind ADDR    Address to publish on (default 127.0.0.1 -- loopback only)

See docs/06-gui-and-tcl.md.
H
        return 0 ;;
      *) target="$1"; shift ;;
    esac
  done

  [ -z "$target" ] && target="$VVD_XPR"
  export VVD_VNC VVD_VNC_PORT VVD_VNC_BIND

  # VNC exports a headless server, so it selects the display mode itself.
  if [ "$VVD_VNC" -eq 1 ] && [ "$VVD_DISPLAY_MODE" != "xvfb" ]; then
    case "$VVD_DISPLAY_MODE" in
      auto|none) ;;
      *) log_warn "--vnc overrides --display $VVD_DISPLAY_MODE with xvfb" ;;
    esac
    VVD_DISPLAY_MODE=xvfb
  fi

  local mode; mode="$(display_effective_mode)"
  if [ "$mode" = "none" ]; then
    die "no display available.
  Use --display x11 with X forwarding, or --display xvfb for a headless X server
  (then attach with your own VNC/x11vnc), or use 'vvd tcl' for a console."
  fi
  log_info "gui: $(display_describe)"

  local -a argv=(vivado -nojournal -nolog)
  if [ -n "$target" ]; then
    local host_t="$VVD_PROJECT_ROOT/$target"
    case "$target" in /*) host_t="$target" ;; esac
    host_t="$(abspath "$host_t")"
    case "$host_t" in
      "$VVD_PROJECT_ROOT"/*) ;;
      *) die "$target is outside the project root and not visible in the container" ;;
    esac
    argv+=(-source "$VVD_CONTAINER_TCL/open.tcl" -tclargs "$VVD_CONTAINER_WORK/${host_t#"$VVD_PROJECT_ROOT"/}")
  fi

  exec_in_container 1 "${argv[@]}"
}
