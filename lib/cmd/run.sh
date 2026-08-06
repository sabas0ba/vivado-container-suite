# shellcheck shell=bash
# vvd run -- execute a project Tcl script in batch mode.

cmd_run() {
  case "${1:-}" in
    ''|-h|--help)
      echo "vvd run SCRIPT [ARGS...] -- vivado -mode batch -source SCRIPT -tclargs ARGS"
      [ -z "${1:-}" ] && return 2
      return 0 ;;
  esac

  local script="$1"; shift
  local host_script cscript
  case "$script" in
    /*) host_script="$(abspath "$script")" ;;
    *)
      # Relative paths resolve against the current directory first, then the
      # project root -- so `vvd -C proj run scripts/x.tcl` works from anywhere.
      host_script="$(abspath "$PWD/$script")"
      [ -f "$host_script" ] || host_script="$(abspath "$VVD_PROJECT_ROOT/$script")"
      ;;
  esac
  require_file "$host_script" "Tcl script"

  case "$host_script" in
    "$VVD_PROJECT_ROOT"/*) cscript="$VVD_CONTAINER_WORK/${host_script#"$VVD_PROJECT_ROOT"/}" ;;
    *) die "Tcl script lives outside the project root and is not visible in the container:
  script:  $host_script
  project: $VVD_PROJECT_ROOT" ;;
  esac

  log_info "running $cscript"
  vivado_batch "$cscript" "$(basename "${script%.tcl}")" "$@"
}
