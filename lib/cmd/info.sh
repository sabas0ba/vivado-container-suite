# shellcheck shell=bash
# vcs info -- the resolved configuration, and the command a run would issue.

cmd_info() {
  local show_all=0 show_cmd=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) show_all=1; shift ;;
      --cmd) show_cmd=1; shift ;;
      -h|--help) echo "vcs info [--all] [--cmd]   resolved configuration (--all: every key; --cmd: the engine command line)"; return 0 ;;
      *) die_usage "vcs info: unexpected argument: $1" ;;
    esac
  done

  engine_detect || true

  printf 'vcs             %s\n' "$VCS_VERSION"
  printf 'suite root      %s\n' "$VCS_ROOT"
  printf 'project root    %s\n' "$VCS_PROJECT_ROOT"
  printf 'project         %s\n' "$VCS_PROJECT_NAME"
  printf 'engine          %s%s\n' "${VCS_ENGINE_BIN:-<none found>}" \
         "$( [ "$VCS_ENGINE_ROOTLESS" -eq 1 ] && printf ' (rootless)')"
  printf 'image           %s\n' "$VCS_IMAGE"
  printf 'vivado          %s (%s, mode=%s)\n' "$VCS_VIVADO_VERSION" "$VCS_VIVADO_EDITION" "$VCS_VIVADO_MODE"
  [ "$VCS_VIVADO_MODE" = "mount" ] && printf 'vivado root     %s\n' "$VCS_XILINX_ROOT"
  printf 'license         %s\n' "$(license_describe)"
  printf 'display         %s\n' "$(display_describe)"
  printf 'jtag            %s\n' "$(jtag_describe)"
  printf 'build dir       %s\n' "$VCS_PROJECT_ROOT/$VCS_BUILD_DIR"
  printf 'cache dir       %s\n' "$VCS_CACHE_DIR"
  printf 'flow            %s\n' "$VCS_FLOW_MODE"
  printf 'part / top      %s / %s\n' "${VCS_PART:-<unset>}" "${VCS_TOP:-<unset>}"
  printf 'jobs            %s\n' "$VCS_JOBS"

  if [ "$show_all" -eq 1 ]; then
    printf '\n--- all configuration keys ---\n'
    config_dump
  fi

  if [ "$show_cmd" -eq 1 ]; then
    printf '\n--- container command ---\n'
    build_container_args 0
    quote_cmd "$VCS_ENGINE_BIN" "${VCS_RUN_ARGV[@]}" "$VCS_IMAGE" vivado -version
    printf '\n'
  fi
}
