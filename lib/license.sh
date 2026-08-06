# shellcheck shell=bash
# License injection.
#
# Rule: a license is *never* part of the image.  It is supplied at `run` time by
# the caller and reaches the container as either an environment variable (a
# floating license server) or a read-only bind mount (a node-locked .lic file).

# license_resolve -- pick a spec from, in order: VVD_LICENSE (config/flag),
# XILINXD_LICENSE_FILE from the host environment, ~/.Xilinx/Xilinx.lic.
license_resolve() {
  if [ -n "${VVD_LICENSE:-}" ]; then printf '%s' "$VVD_LICENSE"; return 0; fi
  if [ -n "${XILINXD_LICENSE_FILE:-}" ]; then printf '%s' "$XILINXD_LICENSE_FILE"; return 0; fi
  if [ -f "$HOME/.Xilinx/Xilinx.lic" ]; then printf '%s' "$HOME/.Xilinx/Xilinx.lic"; return 0; fi
  printf 'none'
}

license_kind() { # <spec>
  case "$1" in
    none|'')      printf 'none' ;;
    dir:*)        printf 'dir' ;;
    *@*)          printf 'server' ;;
    /*|./*|../*)  printf 'file' ;;
    *)            printf 'unknown' ;;
  esac
}

# license_args -- emit engine run arguments (one per line) for the resolved spec.
license_args() {
  local spec kind
  spec="$(license_resolve)"
  kind="$(license_kind "$spec")"

  case "$kind" in
    none)
      log_debug "license: none supplied"
      ;;
    server)
      # Multiple servers may be colon separated; all are host:port references,
      # so nothing is mounted.
      log_debug "license: floating server(s) $spec"
      printf -- '--env\nXILINXD_LICENSE_FILE=%s\n' "$spec"
      ;;
    file)
      local host_path
      host_path="$(abspath "$spec")"
      [ -f "$host_path" ] || die "license file not found: $host_path"
      log_debug "license: node-locked file $host_path"
      mount_ro "$host_path" "$VVD_CONTAINER_LICENSE_DIR/Xilinx.lic"
      printf -- '--env\nXILINXD_LICENSE_FILE=%s/Xilinx.lic\n' "$VVD_CONTAINER_LICENSE_DIR"
      ;;
    dir)
      local host_dir="${spec#dir:}"
      host_dir="$(abspath "$host_dir")"
      [ -d "$host_dir" ] || die "license directory not found: $host_dir"
      log_debug "license: directory $host_dir"
      mount_ro "$host_dir" "$VVD_CONTAINER_LICENSE_DIR"
      printf -- '--env\nXILINXD_LICENSE_FILE=%s\n' "$VVD_CONTAINER_LICENSE_DIR"
      ;;
    *)
      die "unrecognised VVD_LICENSE spec: '$spec' (expected port@host, /path/to.lic, dir:/path, or none)"
      ;;
  esac

  # ~/.Xilinx also holds installed-license metadata and tool preferences.
  local dotdir="${VVD_XILINX_DOTDIR:-}"
  if [ -z "$dotdir" ] && [ -d "$HOME/.Xilinx" ]; then dotdir="$HOME/.Xilinx"; fi
  if [ -n "$dotdir" ]; then
    dotdir="$(abspath "$dotdir")"
    [ -d "$dotdir" ] || die "VVD_XILINX_DOTDIR is not a directory: $dotdir"
    mount_ro "$dotdir" "$VVD_CONTAINER_HOME/.Xilinx"
  fi
}

license_describe() {
  local spec kind
  spec="$(license_resolve)"
  kind="$(license_kind "$spec")"
  case "$kind" in
    none)   printf 'none (tools requiring a license will fail)' ;;
    server) printf 'floating server: %s' "$spec" ;;
    file)   printf 'node-locked file: %s (mounted read-only)' "$spec" ;;
    dir)    printf 'directory: %s (mounted read-only)' "${spec#dir:}" ;;
    *)      printf 'INVALID: %s' "$spec" ;;
  esac
}
