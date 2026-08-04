# shellcheck shell=bash
cmd_synth() {
  case "${1:-}" in
    -h|--help) printf 'vcs %s -- %s\n' "synth" "synthesise the design"; return 0 ;;
  esac
  [ $# -eq 0 ] || die_usage "vcs synth takes no arguments"
  flow_stage synth
}
