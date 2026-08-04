# shellcheck shell=bash
# vcs pull -- fetch a prebuilt image by digest and retag it locally.

cmd_pull() {
  local ref="${1:-}"
  case "$ref" in
    -h|--help)
      cat <<'H'
vcs pull [REF]

  With no argument, pulls the reference recorded under the `prebuilt` key in
  config/images.lock.  REF must be digest-pinned (contain '@sha256:') -- pulling
  a floating tag would defeat the point of the lock files.
H
      return 0 ;;
  esac

  if [ -z "$ref" ]; then
    ref="$(lock_lookup "$VCS_ROOT/config/images.lock" prebuilt)"
  fi
  case "$ref" in
    *@sha256:*) ;;
    *) die "refusing to pull an unpinned reference: $ref
  Pass a digest-pinned reference (name@sha256:...) or add one to config/images.lock." ;;
  esac

  engine_require
  log_info "pulling $ref"
  engine_run pull --platform "$VCS_PLATFORM" "$ref"
  engine_run tag "$ref" "$VCS_IMAGE"
  [ "${VCS_DRY_RUN:-0}" -eq 1 ] || log_ok "tagged as $VCS_IMAGE"
}
