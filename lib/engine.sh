# shellcheck shell=bash
# Container engine abstraction: docker and podman.

# Canonical in-container paths.  Nothing else in the tree hard-codes these.
VCS_CONTAINER_WORK=/work
VCS_CONTAINER_XILINX_ROOT=/opt/Xilinx
VCS_CONTAINER_HOME=/home/vivado
VCS_CONTAINER_LICENSE_DIR=/opt/vcs/license
VCS_CONTAINER_TCL=/opt/vcs/tcl
export VCS_CONTAINER_WORK VCS_CONTAINER_XILINX_ROOT VCS_CONTAINER_HOME
export VCS_CONTAINER_LICENSE_DIR VCS_CONTAINER_TCL

VCS_ENGINE_BIN=""
VCS_ENGINE_KIND=""
VCS_ENGINE_ROOTLESS=0

engine_detect() {
  [ -n "$VCS_ENGINE_BIN" ] && return 0
  local candidates=()
  case "$VCS_ENGINE" in
    auto)   candidates=(podman docker) ;;
    podman) candidates=(podman) ;;
    docker) candidates=(docker) ;;
    *)      die "VCS_ENGINE must be auto, docker or podman (got: $VCS_ENGINE)" ;;
  esac

  local c
  for c in "${candidates[@]}"; do
    if have "$c"; then VCS_ENGINE_BIN="$c"; VCS_ENGINE_KIND="$c"; break; fi
  done
  [ -n "$VCS_ENGINE_BIN" ] ||
    die "no container engine found (looked for: ${candidates[*]}); install podman or docker"

  if [ "$VCS_ENGINE_KIND" = "podman" ]; then
    [ "$(id -u)" -ne 0 ] && VCS_ENGINE_ROOTLESS=1
  fi
  log_debug "engine: $VCS_ENGINE_BIN (rootless=$VCS_ENGINE_ROOTLESS)"
}

engine_available() {
  engine_detect
  "$VCS_ENGINE_BIN" info >/dev/null 2>&1
}

engine_require() {
  engine_detect
  engine_available ||
    die "$VCS_ENGINE_BIN is installed but not usable (daemon down, or no permission). Try 'vcs doctor'."
}

# engine_volume_flag -- SELinux relabelling suffix for bind mounts.
engine_volume_suffix() {
  if [ "$VCS_ENGINE_KIND" = "podman" ] && [ -e /sys/fs/selinux ]; then
    printf ':z'
  fi
}

# mount_ro <host> <container> ; mount_rw <host> <container>
mount_ro() { printf -- '--volume\n%s:%s:ro%s\n' "$1" "$2" "$(engine_volume_suffix)"; }
mount_rw() { printf -- '--volume\n%s:%s:rw%s\n' "$1" "$2" "$(engine_volume_suffix)"; }

# engine_host_gateway_args -- how the container reaches a service on the host.
engine_host_gateway_args() {
  # Host networking already puts the container on the host's stack.
  [ "${VCS_NETWORK:-}" = "host" ] && return 0
  if [ "$VCS_ENGINE_KIND" = "docker" ]; then
    printf -- '--add-host\nhost.docker.internal:host-gateway\n'
    printf -- '--add-host\nhost.containers.internal:host-gateway\n'
  fi
}

engine_host_gateway_name() {
  if [ "$VCS_ENGINE_KIND" = "podman" ]; then printf 'host.containers.internal'
  else printf 'host.docker.internal'; fi
}

# engine_user_args -- keep files written into /work owned by the invoking user.
engine_user_args() {
  case "$VCS_USER_MODE" in
    root) return 0 ;;
    match) ;;
    *) die "VCS_USER_MODE must be 'match' or 'root' (got: $VCS_USER_MODE)" ;;
  esac
  if [ "$VCS_ENGINE_ROOTLESS" -eq 1 ]; then
    # Rootless podman already maps the invoking user; keep-id makes the in-
    # container uid match so bind-mounted files keep their ownership.
    printf -- '--userns\nkeep-id\n'
  else
    # Enter as root, let the entrypoint create a matching account and drop.
    printf -- '--env\nVCS_UID=%s\n--env\nVCS_GID=%s\n' "$(id -u)" "$(id -g)"
  fi
}

engine_run() {
  log_debug "exec: $(quote_cmd "$VCS_ENGINE_BIN" "$@")"
  if [ "${VCS_DRY_RUN:-0}" -eq 1 ]; then
    quote_cmd "$VCS_ENGINE_BIN" "$@"
    printf '\n'
    return 0
  fi
  "$VCS_ENGINE_BIN" "$@"
}

engine_exec() {
  log_debug "exec: $(quote_cmd "$VCS_ENGINE_BIN" "$@")"
  if [ "${VCS_DRY_RUN:-0}" -eq 1 ]; then
    quote_cmd "$VCS_ENGINE_BIN" "$@"
    printf '\n'
    return 0
  fi
  exec "$VCS_ENGINE_BIN" "$@"
}

image_exists() {
  engine_detect
  "$VCS_ENGINE_BIN" image inspect "$1" >/dev/null 2>&1
}

# lock_lookup <lockfile> <key> -- read a '<key>|<value>' lock entry.
lock_lookup() {
  local file="$1" key="$2" line
  require_file "$file" "lock file"
  line="$(grep -E "^${key}\|" "$file" | head -n1)" || true
  [ -n "$line" ] || die "$file: no entry for '$key'"
  printf '%s' "${line#*|}"
}
