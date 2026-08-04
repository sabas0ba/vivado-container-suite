# shellcheck shell=bash
# vcs run -- execute a project Tcl script in batch mode.

cmd_run() {
  case "${1:-}" in
    ''|-h|--help)
      echo "vcs run SCRIPT [ARGS...] -- vivado -mode batch -source SCRIPT -tclargs ARGS"
      [ -z "${1:-}" ] && return 2
      return 0 ;;
  esac

  local script="$1"; shift
  local host_script cscript
  case "$script" in
    /*) host_script="$(abspath "$script")" ;;
    *)
      # Relative paths resolve against the current directory first, then the
      # project root -- so `vcs -C proj run scripts/x.tcl` works from anywhere.
      host_script="$(abspath "$PWD/$script")"
      [ -f "$host_script" ] || host_script="$(abspath "$VCS_PROJECT_ROOT/$script")"
      ;;
  esac
  require_file "$host_script" "Tcl script"

  case "$host_script" in
    "$VCS_PROJECT_ROOT"/*) cscript="$VCS_CONTAINER_WORK/${host_script#"$VCS_PROJECT_ROOT"/}" ;;
    *) die "Tcl script lives outside the project root and is not visible in the container:
  script:  $host_script
  project: $VCS_PROJECT_ROOT" ;;
  esac

  log_info "running $cscript"
  vivado_batch "$cscript" "$(basename "${script%.tcl}")" "$@"
}
