# shellcheck shell=bash
# Assembly of the container invocation.
#
# The argument emitters below print one engine argument per line.  They are
# collected through command substitution, which means they run in a subshell --
# so every collection point checks the status and aborts, otherwise a `die`
# inside an emitter would be silently swallowed and the container would start
# with a half-built command line.  Anything that has to mutate shell state
# (temporary files, cleanup registrations) happens in a *_prepare function that
# runs in the parent instead.

VCS_TEMP_FILES=()
vcs_cleanup() {
  # Runs from an EXIT trap: it must not disturb the script's exit status.
  local rc=$? f
  for f in "${VCS_TEMP_FILES[@]:-}"; do [ -n "$f" ] && rm -f "$f"; done
  return "$rc"
}

# _collect <array-name> <emitter-function> [args...]
# Appends the emitter's lines to the named array.  Aborts the whole CLI if the
# emitter failed -- it has already printed why.
_collect() {
  local __arr="$1"; shift
  local __out __line
  __out="$("$@")" || exit 1
  [ -n "$__out" ] || return 0
  while IFS= read -r __line; do
    [ -n "$__line" ] || continue
    eval "$__arr+=(\"\$__line\")"
  done <<<"$__out"
}

# vivado_versions_present <xilinx-root> -- for error messages.
vivado_versions_present() {
  local d="$1/$VCS_VIVADO_EDITION" out=""
  [ -d "$d" ] || { printf 'none (%s does not exist)' "$d"; return 0; }
  local e
  for e in "$d"/*; do
    [ -d "$e" ] && [ -f "$e/settings64.sh" ] && out="$out $(basename "$e")"
  done
  printf '%s' "${out:- none}"
}

# vivado_mount_args -- how Vivado itself gets into the container.
vivado_mount_args() {
  case "$VCS_VIVADO_MODE" in
    image)
      # Vivado lives in the image; nothing to mount.
      log_debug "vivado: baked into image $VCS_IMAGE"
      ;;
    none)
      # No Vivado at all.  Everything that does not need the tools still works,
      # which is what lets CI exercise the container on a runner without an
      # installation.
      log_debug "vivado: not provided (VCS_VIVADO_MODE=none)"
      ;;
    mount)
      local root
      root="$(abspath "$VCS_XILINX_ROOT")"
      [ -d "$root" ] || die "VCS_XILINX_ROOT does not exist on this host: $root
  Either install Vivado there, point VCS_XILINX_ROOT at your install, or build
  an image with Vivado inside it (VCS_VIVADO_MODE=image, see docs/03-image-build.md)."
      local settings="$root/$VCS_VIVADO_EDITION/$VCS_VIVADO_VERSION/settings64.sh"
      [ -f "$settings" ] || die "Vivado $VCS_VIVADO_VERSION not found under $root
  Expected:  $settings
  Available: $(vivado_versions_present "$root")"
      mount_ro "$root" "$VCS_CONTAINER_XILINX_ROOT"
      ;;
    *)
      die "VCS_VIVADO_MODE must be 'mount', 'image' or 'none' (got: $VCS_VIVADO_MODE)" ;;
  esac
}

# extra_mount_args -- VCS_EXTRA_MOUNTS is a whitespace separated list of
# host:container[:mode] triples (e.g. IP repositories, shared board files).
extra_mount_args() {
  local spec host rest
  for spec in $VCS_EXTRA_MOUNTS; do
    [ -n "$spec" ] || continue
    host="${spec%%:*}"; rest="${spec#*:}"
    [ "$rest" != "$spec" ] || die "VCS_EXTRA_MOUNTS entry needs host:container[:mode]: $spec"
    host="$(abspath "$host")"
    [ -e "$host" ] || die "VCS_EXTRA_MOUNTS source does not exist: $host"
    case "$rest" in
      *:ro|*:rw) printf -- '--volume\n%s:%s%s\n' "$host" "$rest" "$(engine_volume_suffix)" ;;
      *)         printf -- '--volume\n%s:%s:rw%s\n' "$host" "$rest" "$(engine_volume_suffix)" ;;
    esac
  done
}

extra_env_args() {
  local kv
  for kv in $VCS_EXTRA_ENV; do
    [ -n "$kv" ] || continue
    case "$kv" in
      *=*) printf -- '--env\n%s\n' "$kv" ;;
      *)   [ -n "${!kv+x}" ] || die "VCS_EXTRA_ENV names $kv but it is unset in the environment"
           printf -- '--env\n%s=%s\n' "$kv" "${!kv}" ;;
    esac
  done
}

resource_args() {
  [ -n "$VCS_MEMORY" ]  && printf -- '--memory\n%s\n'  "$VCS_MEMORY"
  [ -n "$VCS_CPUS" ]    && printf -- '--cpus\n%s\n'    "$VCS_CPUS"
  [ -n "$VCS_NETWORK" ] && printf -- '--network\n%s\n' "$VCS_NETWORK"
  [ -n "$VCS_TMPFS_SIZE" ] && printf -- '--tmpfs\n/tmp:exec,size=%s\n' "$VCS_TMPFS_SIZE"
  # Vivado's synthesis and place-and-route are memory hungry; the default 64 MB
  # /dev/shm makes multi-threaded runs abort.
  printf -- '--shm-size\n1g\n'
  return 0
}

# vcs_env_args -- configuration the in-container scripts need.
vcs_env_args() {
  local k
  for k in VCS_VIVADO_VERSION VCS_VIVADO_EDITION VCS_VIVADO_MODE \
           VCS_PROJECT_NAME VCS_BUILD_DIR VCS_TOP VCS_PART VCS_BOARD_PART \
           VCS_SOURCES VCS_VHDL_SOURCES VCS_SV_SOURCES VCS_CONSTRAINTS \
           VCS_IP VCS_BD VCS_FLOW_MODE VCS_XPR VCS_SYNTH_ARGS \
           VCS_IMPL_DIRECTIVE VCS_ALLOW_TIMING_VIOLATION \
           VCS_GENERICS VCS_INCLUDE_DIRS VCS_PRE_TCL VCS_POST_TCL \
           VCS_SIM_TOP VCS_SIM_SOURCES VCS_SIM_VHDL_SOURCES VCS_SIM_TIME \
           VCS_SIM_LIBS VCS_SIM_XELAB_ARGS VCS_SIM_XVLOG_ARGS VCS_SIM_WAVES \
           VCS_JOBS VCS_HW_SERVER_PORT VCS_LOG_LEVEL \
           VCS_SELFTEST_REQUIRE_VIVADO; do
    printf -- '--env\n%s=%s\n' "$k" "${!k-}"
  done
  printf -- '--env\nVCS_CONTAINER_WORK=%s\n' "$VCS_CONTAINER_WORK"
  printf -- '--env\nVCS_CONTAINER_XILINX_ROOT=%s\n' "$VCS_CONTAINER_XILINX_ROOT"
  printf -- '--env\nVCS_CONTAINER_TCL=%s\n' "$VCS_CONTAINER_TCL"
  printf -- '--env\nHOME=%s\n' "$VCS_CONTAINER_HOME"
}

_emit_mounts() {
  mount_rw "$VCS_PROJECT_ROOT" "$VCS_CONTAINER_WORK"
  mount_rw "$VCS_CACHE_DIR" "$VCS_CONTAINER_HOME"
  mount_ro "$VCS_ROOT/tcl" "$VCS_CONTAINER_TCL"
  mount_ro "$VCS_ROOT/container" /opt/vcs/lib
  vivado_mount_args
  extra_mount_args
}

# build_container_args <interactive:0|1>
# Fills VCS_RUN_ARGV with the `run` argv up to (not including) the image name.
VCS_RUN_ARGV=()
build_container_args() {
  local interactive="$1"
  local dmode
  dmode="$(display_effective_mode)" || exit 1
  display_prepare "$dmode"

  mkdir -p "$VCS_CACHE_DIR" ||
    die "cannot create the cache directory: $VCS_CACHE_DIR"

  VCS_RUN_ARGV=(run --rm)
  [ "$interactive" -eq 1 ] && VCS_RUN_ARGV+=(--interactive --tty)
  VCS_RUN_ARGV+=(--platform "$VCS_PLATFORM")
  VCS_RUN_ARGV+=(--workdir "$VCS_CONTAINER_WORK")
  VCS_RUN_ARGV+=(--hostname "vcs-${VCS_PROJECT_NAME//[^A-Za-z0-9_-]/-}")
  # Vivado spawns a lot of threads and opens a lot of files.
  VCS_RUN_ARGV+=(--ulimit "nofile=8192:8192")

  _collect VCS_RUN_ARGV _emit_mounts
  _collect VCS_RUN_ARGV engine_user_args
  _collect VCS_RUN_ARGV license_args
  _collect VCS_RUN_ARGV display_args "$dmode"
  _collect VCS_RUN_ARGV jtag_args
  _collect VCS_RUN_ARGV extra_env_args
  _collect VCS_RUN_ARGV resource_args
  _collect VCS_RUN_ARGV vcs_env_args

  if [ -n "$VCS_EXTRA_RUN_ARGS" ]; then
    # Deliberately word-split: this is a raw pass-through for the engine.
    # shellcheck disable=SC2206
    local -a passthrough=($VCS_EXTRA_RUN_ARGS)
    VCS_RUN_ARGV+=("${passthrough[@]}")
  fi
}

image_require() {
  [ "${VCS_DRY_RUN:-0}" -eq 1 ] && return 0
  image_exists "$VCS_IMAGE" && return 0
  die "image not found: $VCS_IMAGE
  Build it with:  vcs build
  (or set VCS_IMAGE to an image you already have)"
}

# run_in_container <interactive> <argv...>
run_in_container() {
  local interactive="$1"; shift
  engine_require
  image_require
  build_container_args "$interactive"
  engine_run "${VCS_RUN_ARGV[@]}" "$VCS_IMAGE" "$@"
}

# exec_in_container -- same, but replaces this process, which is what gives an
# interactive Vivado session correct signal and terminal handling.
exec_in_container() {
  local interactive="$1"; shift
  engine_require
  image_require
  build_container_args "$interactive"
  if [ "${VCS_DRY_RUN:-0}" -eq 1 ]; then
    engine_run "${VCS_RUN_ARGV[@]}" "$VCS_IMAGE" "$@"
  else
    engine_exec "${VCS_RUN_ARGV[@]}" "$VCS_IMAGE" "$@"
  fi
}
