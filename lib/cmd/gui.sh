# shellcheck shell=bash
# vcs gui -- the Vivado IDE.

cmd_gui() {
  local target=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        cat <<'H'
vcs gui [XPR|DCP]

  Launches the Vivado IDE.  With no argument it opens VCS_XPR if set, otherwise
  an empty IDE.  A checkpoint (.dcp) from the non-project flow can be opened
  directly, which is the usual way to inspect a placed & routed design.

  Display transport is chosen by --display / VCS_DISPLAY_MODE:
    auto     X11 if DISPLAY is set, else headless Xvfb  (default)
    x11      X socket + a per-run untrusted xauth cookie
    wayland  through the compositor's XWayland socket
    xvfb     headless; pair with a VNC/X client of your own
See docs/06-gui-and-tcl.md.
H
        return 0 ;;
      *) target="$1"; shift ;;
    esac
  done

  [ -z "$target" ] && target="$VCS_XPR"

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
