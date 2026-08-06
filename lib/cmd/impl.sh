# shellcheck shell=bash
cmd_impl() {
  case "${1:-}" in
    -h|--help) printf 'vvd %s -- %s\n' "impl" "place & route (synthesises first if needed)"; return 0 ;;
  esac
  [ $# -eq 0 ] || die_usage "vvd impl takes no arguments"
  flow_stage impl
}
