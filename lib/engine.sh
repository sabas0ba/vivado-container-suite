# shellcheck shell=bash
# Container engine abstraction: docker and podman.

# Canonical in-container paths.  Nothing else in the tree hard-codes these.
VVD_CONTAINER_WORK=/work
VVD_CONTAINER_XILINX_ROOT=/opt/Xilinx
VVD_CONTAINER_HOME=/home/vivado
VVD_CONTAINER_LICENSE_DIR=/opt/vvd/license
VVD_CONTAINER_TCL=/opt/vvd/tcl
export VVD_CONTAINER_WORK VVD_CONTAINER_XILINX_ROOT VVD_CONTAINER_HOME
export VVD_CONTAINER_LICENSE_DIR VVD_CONTAINER_TCL

VVD_ENGINE_BIN=""
VVD_ENGINE_KIND=""
VVD_ENGINE_ROOTLESS=0

engine_detect() {
  [ -n "$VVD_ENGINE_BIN" ] && return 0
  local candidates=()
  case "$VVD_ENGINE" in
    auto)   candidates=(podman docker) ;;
    podman) candidates=(podman) ;;
    docker) candidates=(docker) ;;
    *)      die "VVD_ENGINE must be auto, docker or podman (got: $VVD_ENGINE)" ;;
  esac

  local c
  for c in "${candidates[@]}"; do
    if have "$c"; then VVD_ENGINE_BIN="$c"; VVD_ENGINE_KIND="$c"; break; fi
  done
  [ -n "$VVD_ENGINE_BIN" ] ||
    die "no container engine found (looked for: ${candidates[*]}); install podman or docker"

  if [ "$VVD_ENGINE_KIND" = "podman" ]; then
    [ "$(id -u)" -ne 0 ] && VVD_ENGINE_ROOTLESS=1
  fi
  log_debug "engine: $VVD_ENGINE_BIN (rootless=$VVD_ENGINE_ROOTLESS)"
}

engine_available() {
  engine_detect
  "$VVD_ENGINE_BIN" info >/dev/null 2>&1
}

engine_require() {
  engine_detect
  engine_available ||
    die "$VVD_ENGINE_BIN is installed but not usable (daemon down, or no permission). Try 'vvd doctor'."
}

# engine_volume_flag -- SELinux relabelling suffix for bind mounts.
engine_volume_suffix() {
  if [ "$VVD_ENGINE_KIND" = "podman" ] && [ -e /sys/fs/selinux ]; then
    printf ':z'
  fi
}

# mount_ro <host> <container> ; mount_rw <host> <container>
mount_ro() { printf -- '--volume\n%s:%s:ro%s\n' "$1" "$2" "$(engine_volume_suffix)"; }
mount_rw() { printf -- '--volume\n%s:%s:rw%s\n' "$1" "$2" "$(engine_volume_suffix)"; }

# engine_host_gateway_args -- how the container reaches a service on the host.
engine_host_gateway_args() {
  # Host networking already puts the container on the host's stack.
  [ "${VVD_NETWORK:-}" = "host" ] && return 0
  if [ "$VVD_ENGINE_KIND" = "docker" ]; then
    printf -- '--add-host\nhost.docker.internal:host-gateway\n'
    printf -- '--add-host\nhost.containers.internal:host-gateway\n'
  fi
}

engine_host_gateway_name() {
  if [ "$VVD_ENGINE_KIND" = "podman" ]; then printf 'host.containers.internal'
  else printf 'host.docker.internal'; fi
}

# engine_user_args -- keep files written into /work owned by the invoking user.
engine_user_args() {
  case "$VVD_USER_MODE" in
    root) return 0 ;;
    match) ;;
    *) die "VVD_USER_MODE must be 'match' or 'root' (got: $VVD_USER_MODE)" ;;
  esac
  if [ "$VVD_ENGINE_ROOTLESS" -eq 1 ]; then
    # Rootless podman already maps the invoking user; keep-id makes the in-
    # container uid match so bind-mounted files keep their ownership.
    printf -- '--userns\nkeep-id\n'
  else
    # Enter as root, let the entrypoint create a matching account and drop.
    printf -- '--env\nVVD_UID=%s\n--env\nVVD_GID=%s\n' "$(id -u)" "$(id -g)"
  fi
}

engine_run() {
  log_debug "exec: $(quote_cmd "$VVD_ENGINE_BIN" "$@")"
  if [ "${VVD_DRY_RUN:-0}" -eq 1 ]; then
    quote_cmd "$VVD_ENGINE_BIN" "$@"
    printf '\n'
    return 0
  fi
  "$VVD_ENGINE_BIN" "$@"
}

engine_exec() {
  log_debug "exec: $(quote_cmd "$VVD_ENGINE_BIN" "$@")"
  if [ "${VVD_DRY_RUN:-0}" -eq 1 ]; then
    quote_cmd "$VVD_ENGINE_BIN" "$@"
    printf '\n'
    return 0
  fi
  exec "$VVD_ENGINE_BIN" "$@"
}

image_exists() {
  engine_detect
  "$VVD_ENGINE_BIN" image inspect "$1" >/dev/null 2>&1
}

# lock_lookup <lockfile> <key> -- read a '<key>|<value>' lock entry.
lock_lookup() {
  local file="$1" key="$2" line
  require_file "$file" "lock file"
  line="$(grep -E "^${key}\|" "$file" | head -n1)" || true
  [ -n "$line" ] || die "$file: no entry for '$key'"
  printf '%s' "${line#*|}"
}
