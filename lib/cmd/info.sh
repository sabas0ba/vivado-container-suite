# shellcheck shell=bash
# vvd info -- the resolved configuration, and the command a run would issue.

cmd_info() {
  local show_all=0 show_cmd=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) show_all=1; shift ;;
      --cmd) show_cmd=1; shift ;;
      -h|--help) echo "vvd info [--all] [--cmd]   resolved configuration (--all: every key; --cmd: the engine command line)"; return 0 ;;
      *) die_usage "vvd info: unexpected argument: $1" ;;
    esac
  done

  engine_detect || true

  printf 'vvd             %s\n' "$VVD_VERSION"
  printf 'suite root      %s\n' "$VVD_ROOT"
  printf 'project root    %s\n' "$VVD_PROJECT_ROOT"
  printf 'project         %s\n' "$VVD_PROJECT_NAME"
  printf 'engine          %s%s\n' "${VVD_ENGINE_BIN:-<none found>}" \
         "$( [ "$VVD_ENGINE_ROOTLESS" -eq 1 ] && printf ' (rootless)')"
  printf 'image           %s\n' "$VVD_IMAGE"
  printf 'vivado          %s (%s, mode=%s)\n' "$VVD_VIVADO_VERSION" "$VVD_VIVADO_EDITION" "$VVD_VIVADO_MODE"
  [ "$VVD_VIVADO_MODE" = "mount" ] && printf 'vivado root     %s\n' "$VVD_XILINX_ROOT"
  printf 'license         %s\n' "$(license_describe)"
  printf 'display         %s\n' "$(display_describe)"
  printf 'jtag            %s\n' "$(jtag_describe)"
  printf 'build dir       %s\n' "$VVD_PROJECT_ROOT/$VVD_BUILD_DIR"
  printf 'cache dir       %s\n' "$VVD_CACHE_DIR"
  printf 'flow            %s\n' "$VVD_FLOW_MODE"
  printf 'part / top      %s / %s\n' "${VVD_PART:-<unset>}" "${VVD_TOP:-<unset>}"
  printf 'jobs            %s\n' "$VVD_JOBS"

  if [ "$show_all" -eq 1 ]; then
    printf '\n--- all configuration keys ---\n'
    config_dump
  fi

  if [ "$show_cmd" -eq 1 ]; then
    printf '\n--- container command ---\n'
    build_container_args 0
    quote_cmd "$VVD_ENGINE_BIN" "${VVD_RUN_ARGV[@]}" "$VVD_IMAGE" vivado -version
    printf '\n'
  fi
}
