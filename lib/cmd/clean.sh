# shellcheck shell=bash
# vcs clean -- delete generated output.

cmd_clean() {
  local force=0 all=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--force) force=1; shift ;;
      --all)      all=1; shift ;;
      -h|--help)
        echo "vcs clean [-f] [--all]   remove <project>/\$VCS_BUILD_DIR (--all also clears the image cache dir)"
        return 0 ;;
      *) die_usage "vcs clean: unexpected argument: $1" ;;
    esac
  done

  local dir="$VCS_PROJECT_ROOT/$VCS_BUILD_DIR"
  # Guard against a mis-set VCS_BUILD_DIR turning this into `rm -rf $HOME`.
  case "$VCS_BUILD_DIR" in
    ''|/*|.|..|*..*) die "refusing to clean with VCS_BUILD_DIR='$VCS_BUILD_DIR'; it must be a relative path inside the project" ;;
  esac

  if [ -d "$dir" ]; then
    if [ "$force" -eq 0 ] && [ -t 0 ]; then
      printf 'remove %s ? [y/N] ' "$dir" >&2
      local reply; read -r reply
      case "$reply" in y|Y|yes) ;; *) log_info "aborted"; return 0 ;; esac
    fi
    rm -rf "$dir"
    log_ok "removed $dir"
  else
    log_info "nothing to clean ($dir does not exist)"
  fi

  if [ "$all" -eq 1 ] && [ -d "$VCS_CACHE_DIR" ]; then
    rm -rf "${VCS_CACHE_DIR:?}/.Xilinx" "${VCS_CACHE_DIR:?}/.cache"
    log_ok "cleared tool caches under $VCS_CACHE_DIR"
  fi
}
