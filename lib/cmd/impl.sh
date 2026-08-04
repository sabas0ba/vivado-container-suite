# shellcheck shell=bash
cmd_impl() {
  case "${1:-}" in
    -h|--help) printf 'vcs %s -- %s\n' "impl" "place & route (synthesises first if needed)"; return 0 ;;
  esac
  [ $# -eq 0 ] || die_usage "vcs impl takes no arguments"
  flow_stage impl
}
