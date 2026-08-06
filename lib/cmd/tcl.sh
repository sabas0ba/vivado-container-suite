# shellcheck shell=bash
# vvd tcl -- the Vivado Tcl console, or a Tcl script in batch mode.

cmd_tcl() {
  case "${1:-}" in
    -h|--help)
      cat <<'H'
vvd tcl [SCRIPT] [ARGS...]

  With no SCRIPT: an interactive `vivado -mode tcl` console.
  With a SCRIPT:  `vivado -mode batch -source SCRIPT`, with ARGS passed
                  through as -tclargs.  SCRIPT is resolved relative to the
                  project root and must live inside it.

  The suite's own Tcl library is available as `source $env(VVD_CONTAINER_TCL)/lib.tcl`.
H
      return 0 ;;
  esac

  if [ $# -eq 0 ]; then
    log_info "Vivado $VVD_VIVADO_VERSION Tcl console (exit with 'exit')"
    exec_in_container 1 vivado -mode tcl -nojournal -nolog
  else
    # shellcheck source=lib/cmd/run.sh
    . "$VVD_ROOT/lib/cmd/run.sh"
    cmd_run "$@"
  fi
}
