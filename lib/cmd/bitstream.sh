# shellcheck shell=bash
cmd_bitstream() {
  case "${1:-}" in
    -h|--help) printf 'vcs %s -- %s\n' "bitstream" "write the bitstream (implements first if needed)"; return 0 ;;
  esac
  [ $# -eq 0 ] || die_usage "vcs bitstream takes no arguments"
  flow_stage bitstream
}
