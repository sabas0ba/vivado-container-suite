# shellcheck shell=bash
cmd_bitstream() {
  case "${1:-}" in
    -h|--help) printf 'vvd %s -- %s\n' "bitstream" "write the bitstream (implements first if needed)"; return 0 ;;
  esac
  [ $# -eq 0 ] || die_usage "vvd bitstream takes no arguments"
  flow_stage bitstream
}
