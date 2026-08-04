# shellcheck shell=bash
# Helpers shared by the build-flow commands.

# vivado_batch <tcl-file-in-container> [tclargs...]
vivado_batch() {
  local script="$1" logname="$2"; shift 2
  local -a tclargs=()
  [ $# -gt 0 ] && tclargs=(-tclargs "$@")
  run_in_container 0 vivado \
    -mode batch \
    -nojournal \
    -notrace \
    -log "$VCS_CONTAINER_WORK/$VCS_BUILD_DIR/logs/${logname}.log" \
    -source "$script" \
    ${tclargs[@]+"${tclargs[@]}"}
}

# require_project_settings <key...> -- fail early, on the host, with a message
# that names the file the user has to edit.
require_project_settings() {
  local k missing=()
  for k in "$@"; do
    [ -n "${!k-}" ] || missing+=("$k")
  done
  [ ${#missing[@]} -eq 0 ] && return 0
  die "missing required configuration: ${missing[*]}
  Set them in $VCS_PROJECT_ROOT/vcs.conf (see docs/02-configuration.md),
  or pass them on the command line where a flag exists."
}

flow_stage() { # <stage>
  local stage="$1"
  case "$VCS_FLOW_MODE" in
    nonproject)
      require_project_settings VCS_TOP VCS_PART
      ;;
    project)
      [ -n "$VCS_XPR" ] || die "VCS_FLOW_MODE=project requires VCS_XPR to point at a .xpr"
      ;;
    *) die "VCS_FLOW_MODE must be 'nonproject' or 'project' (got: $VCS_FLOW_MODE)" ;;
  esac
  log_info "$stage: $VCS_PROJECT_NAME (${VCS_FLOW_MODE} flow, Vivado $VCS_VIVADO_VERSION)"
  vivado_batch "$VCS_CONTAINER_TCL/flow.tcl" "$stage" "$stage"
}
