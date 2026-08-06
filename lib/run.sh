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

VVD_TEMP_FILES=()
vvd_cleanup() {
  # Runs from an EXIT trap: it must not disturb the script's exit status.
  local rc=$? f
  for f in "${VVD_TEMP_FILES[@]:-}"; do [ -n "$f" ] && rm -f "$f"; done
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
  local d="$1/$VVD_VIVADO_EDITION" out=""
  [ -d "$d" ] || { printf 'none (%s does not exist)' "$d"; return 0; }
  local e
  for e in "$d"/*; do
    [ -d "$e" ] && [ -f "$e/settings64.sh" ] && out="$out $(basename "$e")"
  done
  printf '%s' "${out:- none}"
}

# vivado_mount_args -- how Vivado itself gets into the container.
vivado_mount_args() {
  case "$VVD_VIVADO_MODE" in
    image)
      # Vivado lives in the image; nothing to mount.
      log_debug "vivado: baked into image $VVD_IMAGE"
      ;;
    none)
      # No Vivado at all.  Everything that does not need the tools still works,
      # which is what lets CI exercise the container on a runner without an
      # installation.
      log_debug "vivado: not provided (VVD_VIVADO_MODE=none)"
      ;;
    mount)
      local root
      root="$(abspath "$VVD_XILINX_ROOT")"
      [ -d "$root" ] || die "VVD_XILINX_ROOT does not exist on this host: $root
  Either install Vivado there, point VVD_XILINX_ROOT at your install, or build
  an image with Vivado inside it (VVD_VIVADO_MODE=image, see docs/03-image-build.md)."
      local settings="$root/$VVD_VIVADO_EDITION/$VVD_VIVADO_VERSION/settings64.sh"
      [ -f "$settings" ] || die "Vivado $VVD_VIVADO_VERSION not found under $root
  Expected:  $settings
  Available: $(vivado_versions_present "$root")"
      mount_ro "$root" "$VVD_CONTAINER_XILINX_ROOT"
      ;;
    *)
      die "VVD_VIVADO_MODE must be 'mount', 'image' or 'none' (got: $VVD_VIVADO_MODE)" ;;
  esac
}

# extra_mount_args -- VVD_EXTRA_MOUNTS is a whitespace separated list of
# host:container[:mode] triples (e.g. IP repositories, shared board files).
extra_mount_args() {
  local spec host rest
  for spec in $VVD_EXTRA_MOUNTS; do
    [ -n "$spec" ] || continue
    host="${spec%%:*}"; rest="${spec#*:}"
    [ "$rest" != "$spec" ] || die "VVD_EXTRA_MOUNTS entry needs host:container[:mode]: $spec"
    host="$(abspath "$host")"
    [ -e "$host" ] || die "VVD_EXTRA_MOUNTS source does not exist: $host"
    case "$rest" in
      *:ro|*:rw) printf -- '--volume\n%s:%s%s\n' "$host" "$rest" "$(engine_volume_suffix)" ;;
      *)         printf -- '--volume\n%s:%s:rw%s\n' "$host" "$rest" "$(engine_volume_suffix)" ;;
    esac
  done
}

extra_env_args() {
  local kv
  for kv in $VVD_EXTRA_ENV; do
    [ -n "$kv" ] || continue
    case "$kv" in
      *=*) printf -- '--env\n%s\n' "$kv" ;;
      *)   [ -n "${!kv+x}" ] || die "VVD_EXTRA_ENV names $kv but it is unset in the environment"
           printf -- '--env\n%s=%s\n' "$kv" "${!kv}" ;;
    esac
  done
}

resource_args() {
  [ -n "$VVD_MEMORY" ]  && printf -- '--memory\n%s\n'  "$VVD_MEMORY"
  [ -n "$VVD_CPUS" ]    && printf -- '--cpus\n%s\n'    "$VVD_CPUS"
  [ -n "$VVD_NETWORK" ] && printf -- '--network\n%s\n' "$VVD_NETWORK"
  [ -n "$VVD_TMPFS_SIZE" ] && printf -- '--tmpfs\n/tmp:exec,size=%s\n' "$VVD_TMPFS_SIZE"
  # Vivado's synthesis and place-and-route are memory hungry; the default 64 MB
  # /dev/shm makes multi-threaded runs abort.
  printf -- '--shm-size\n1g\n'
  return 0
}

# vvd_env_args -- configuration the in-container scripts need.
vvd_env_args() {
  local k
  for k in VVD_VIVADO_VERSION VVD_VIVADO_EDITION VVD_VIVADO_MODE \
           VVD_PROJECT_NAME VVD_BUILD_DIR VVD_TOP VVD_PART VVD_BOARD_PART \
           VVD_SOURCES VVD_VHDL_SOURCES VVD_SV_SOURCES VVD_CONSTRAINTS \
           VVD_IP VVD_BD VVD_FLOW_MODE VVD_XPR VVD_SYNTH_ARGS \
           VVD_IMPL_DIRECTIVE VVD_ALLOW_TIMING_VIOLATION \
           VVD_GENERICS VVD_INCLUDE_DIRS VVD_PRE_TCL VVD_POST_TCL \
           VVD_SIM_TOP VVD_SIM_SOURCES VVD_SIM_VHDL_SOURCES VVD_SIM_TIME \
           VVD_SIM_LIBS VVD_SIM_XELAB_ARGS VVD_SIM_XVLOG_ARGS VVD_SIM_WAVES \
           VVD_JOBS VVD_HW_SERVER_PORT VVD_LOG_LEVEL \
           VVD_SELFTEST_REQUIRE_VIVADO; do
    printf -- '--env\n%s=%s\n' "$k" "${!k-}"
  done
  printf -- '--env\nVVD_CONTAINER_WORK=%s\n' "$VVD_CONTAINER_WORK"
  printf -- '--env\nVVD_CONTAINER_XILINX_ROOT=%s\n' "$VVD_CONTAINER_XILINX_ROOT"
  printf -- '--env\nVVD_CONTAINER_TCL=%s\n' "$VVD_CONTAINER_TCL"
  printf -- '--env\nHOME=%s\n' "$VVD_CONTAINER_HOME"
}

_emit_mounts() {
  mount_rw "$VVD_PROJECT_ROOT" "$VVD_CONTAINER_WORK"
  mount_rw "$VVD_CACHE_DIR" "$VVD_CONTAINER_HOME"
  mount_ro "$VVD_ROOT/tcl" "$VVD_CONTAINER_TCL"
  mount_ro "$VVD_ROOT/container" /opt/vvd/lib
  vivado_mount_args
  extra_mount_args
}

# build_container_args <interactive:0|1>
# Fills VVD_RUN_ARGV with the `run` argv up to (not including) the image name.
VVD_RUN_ARGV=()
build_container_args() {
  local interactive="$1"
  local dmode
  dmode="$(display_effective_mode)" || exit 1
  display_prepare "$dmode"

  mkdir -p "$VVD_CACHE_DIR" ||
    die "cannot create the cache directory: $VVD_CACHE_DIR"

  VVD_RUN_ARGV=(run --rm)
  [ "$interactive" -eq 1 ] && VVD_RUN_ARGV+=(--interactive --tty)
  VVD_RUN_ARGV+=(--platform "$VVD_PLATFORM")
  VVD_RUN_ARGV+=(--workdir "$VVD_CONTAINER_WORK")
  VVD_RUN_ARGV+=(--hostname "vvd-${VVD_PROJECT_NAME//[^A-Za-z0-9_-]/-}")
  # Vivado spawns a lot of threads and opens a lot of files.
  VVD_RUN_ARGV+=(--ulimit "nofile=8192:8192")

  _collect VVD_RUN_ARGV _emit_mounts
  _collect VVD_RUN_ARGV engine_user_args
  _collect VVD_RUN_ARGV license_args
  _collect VVD_RUN_ARGV display_args "$dmode"
  _collect VVD_RUN_ARGV jtag_args
  _collect VVD_RUN_ARGV extra_env_args
  _collect VVD_RUN_ARGV resource_args
  _collect VVD_RUN_ARGV vvd_env_args

  if [ -n "$VVD_EXTRA_RUN_ARGS" ]; then
    # Deliberately word-split: this is a raw pass-through for the engine.
    # shellcheck disable=SC2206
    local -a passthrough=($VVD_EXTRA_RUN_ARGS)
    VVD_RUN_ARGV+=("${passthrough[@]}")
  fi
}

image_require() {
  [ "${VVD_DRY_RUN:-0}" -eq 1 ] && return 0
  image_exists "$VVD_IMAGE" && return 0
  die "image not found: $VVD_IMAGE
  Build it with:  vvd build
  (or set VVD_IMAGE to an image you already have)"
}

# run_in_container <interactive> <argv...>
run_in_container() {
  local interactive="$1"; shift
  engine_require
  image_require
  build_container_args "$interactive"
  engine_run "${VVD_RUN_ARGV[@]}" "$VVD_IMAGE" "$@"
}

# exec_in_container -- same, but replaces this process, which is what gives an
# interactive Vivado session correct signal and terminal handling.
exec_in_container() {
  local interactive="$1"; shift
  engine_require
  image_require
  build_container_args "$interactive"
  if [ "${VVD_DRY_RUN:-0}" -eq 1 ]; then
    engine_run "${VVD_RUN_ARGV[@]}" "$VVD_IMAGE" "$@"
  else
    engine_exec "${VVD_RUN_ARGV[@]}" "$VVD_IMAGE" "$@"
  fi
}
