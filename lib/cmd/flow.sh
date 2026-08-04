# shellcheck shell=bash
cmd_flow() {
  case "${1:-}" in
    -h|--help) printf 'vcs %s -- %s\n' "flow" "synth, impl and bitstream in one Vivado invocation"; return 0 ;;
  esac
  [ $# -eq 0 ] || die_usage "vcs flow takes no arguments"
  flow_stage all
}
