# shellcheck shell=bash
# vvd build -- build the container image.

cmd_build() {
  local no_cache=0 progress="auto" installer="" push="" ca_cert="${VVD_CA_CERT:-}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-cache)   no_cache=1; shift ;;
      --progress)   progress="${2:?}"; shift 2 ;;
      --installer)  installer="${2:?}"; shift 2 ;;
      --ca-cert)    ca_cert="${2:?}"; shift 2 ;;
      --tag)        VVD_IMAGE="${2:?}"; shift 2 ;;
      -h|--help)
        cat <<'H'
vvd build [options]

  --installer TARBALL  Vivado web/full installer tarball on the host.  Implies
                       VVD_VIVADO_MODE=image: Vivado is installed INTO the
                       image instead of being bind-mounted from the host.
  --ca-cert FILE       Additional CA certificate to trust *while building*.
                       Needed when a TLS-inspecting proxy sits between the
                       builder and snapshot.ubuntu.com.  It is not added to the
                       image's runtime trust store.
  --tag REF            Image reference to build (default: derived, see `vvd image`)
  --no-cache           Ignore the layer cache
  --progress MODE      Passed to the engine's build (auto|plain|tty)
H
        return 0 ;;
      *) die_usage "vvd build: unexpected argument: $1" ;;
    esac
  done

  engine_require

  local base
  base="$(lock_lookup "$VVD_ROOT/config/images.lock" base)"

  local -a args=(build)
  args+=(--platform "$VVD_PLATFORM")
  args+=(--file "$VVD_ROOT/docker/Dockerfile")
  args+=(--tag "$VVD_IMAGE")
  args+=(--build-arg "BASE_IMAGE=$base")
  args+=(--build-arg "VIVADO_VERSION=$VVD_VIVADO_VERSION")
  args+=(--build-arg "VIVADO_EDITION=$VVD_VIVADO_EDITION")
  [ "$no_cache" -eq 1 ] && args+=(--no-cache)

  # The `cacerts` build context always has to resolve; docker/ is a harmless
  # default, and nothing is copied out of it unless EXTRA_CA_CERT is set.
  if [ -n "$ca_cert" ]; then
    ca_cert="$(abspath "$ca_cert")"
    require_file "$ca_cert" "CA certificate"
    log_info "trusting $ca_cert for the duration of the build only"
    args+=(--build-context "cacerts=$(dirname "$ca_cert")")
    args+=(--build-arg "EXTRA_CA_CERT=$(basename "$ca_cert")")
  else
    args+=(--build-context "cacerts=$VVD_ROOT/docker")
  fi
  [ "$progress" != "auto" ] && args+=(--progress "$progress")

  if [ -n "$installer" ]; then
    installer="$(abspath "$installer")"
    require_file "$installer" "Vivado installer"
    verify_installer "$installer"
    args+=(--build-arg "VIVADO_INSTALLER=$(basename "$installer")")
    args+=(--target vivado)
    # The installer is enormous; hand it to the builder as a bind mount rather
    # than copying it into the build context.
    args+=(--build-context "installer=$(dirname "$installer")")
  else
    args+=(--target base)
  fi

  args+=("$VVD_ROOT")

  log_info "building $VVD_IMAGE (base $base)"
  engine_run "${args[@]}"
  [ "${VVD_DRY_RUN:-0}" -eq 1 ] && return 0
  log_ok "built $VVD_IMAGE"
  [ -n "$push" ] && engine_run push "$VVD_IMAGE"
  return 0
}

# verify_installer <path> -- refuse to build against an installer whose SHA256
# is not in config/vivado-versions.lock.
verify_installer() {
  local path="$1" lock="$VVD_ROOT/config/vivado-versions.lock"
  local expected actual name
  name="$(basename "$path")"
  expected="$(grep -E "^${VVD_VIVADO_VERSION}\|" "$lock" 2>/dev/null | head -n1 | cut -d'|' -f3)" || true

  if [ -z "$expected" ]; then
    die "no SHA256 recorded for Vivado $VVD_VIVADO_VERSION in $lock
  Add a line:  $VVD_VIVADO_VERSION|$name|<sha256>
  Compute it with:  sha256sum $path
  See docs/09-pinning.md for why this is mandatory."
  fi

  log_info "verifying installer checksum (this reads $(du -h "$path" | cut -f1))"
  actual="$(sha256sum "$path" | cut -d' ' -f1)"
  if [ "$actual" != "$expected" ]; then
    die "installer checksum mismatch for Vivado $VVD_VIVADO_VERSION
  expected: $expected
  actual:   $actual
  file:     $path"
  fi
  log_ok "installer checksum matches $lock"
}
