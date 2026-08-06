# shellcheck shell=bash
# vvd selftest -- prove the container can actually do the work.
#
# This is the availability test CI runs.  Every stage is independently
# selectable so a runner without a license, or without a cable, can still
# exercise everything else.

cmd_selftest() {
  local -a stages=()
  local list=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --stage) stages+=("${2:?--stage needs a name}"); shift 2 ;;
      --list)  list=1; shift ;;
      -h|--help)
        cat <<'H'
vvd selftest [--stage NAME]...

Stages (all run by default, in this order):
  image      the image exists and its entrypoint works
  libs       every shared library Vivado dlopen()s resolves
  identity   files created in /work are owned by the invoking user
  display    the configured display transport works end to end
  env        settings64.sh sourced; vivado, xsim, hw_server, xsct on PATH
  version    `vivado -version` reports the expected release
  tcl        a Tcl script runs to completion and can write to /work
  license    the license is visible to the tools
  sim        elaborate and run the bundled smoke testbench
  synth      synthesise the bundled smoke design
  jtag       hw_server is reachable over the configured transport

A stage whose precondition is absent is skipped, not failed.  Set
VVD_SELFTEST_REQUIRE_VIVADO=0 to skip (rather than fail) the stages that need a
Vivado installation -- that is how CI exercises an image built without one.
H
        return 0 ;;
      *) die_usage "vvd selftest: unexpected argument: $1" ;;
    esac
  done

  local all=(image libs identity display env version tcl license sim synth jtag)
  if [ "$list" -eq 1 ]; then printf '%s\n' "${all[@]}"; return 0; fi
  [ ${#stages[@]} -eq 0 ] && stages=("${all[@]}")

  local s rc failed=0 skipped=0
  for s in "${stages[@]}"; do
    declare -F "_selftest_$s" >/dev/null || die_usage "vvd selftest: unknown stage: $s"
    printf '\n=== selftest: %s ===\n' "$s"
    rc=0
    _selftest_"$s" || rc=$?
    case "$rc" in
      0)  log_ok "$s" ;;
      77) log_warn "$s skipped"; skipped=$((skipped + 1)) ;;
      *)  log_error "$s failed (exit $rc)"; failed=$((failed + 1)) ;;
    esac
  done

  printf '\n'
  if [ "$failed" -gt 0 ]; then
    log_error "selftest: $failed stage(s) failed, $skipped skipped"
    return 1
  fi
  log_ok "selftest: all stages passed ($skipped skipped)"
}

_selftest_image() {
  engine_require
  image_exists "$VVD_IMAGE" || { log_error "image $VVD_IMAGE not found"; return 1; }
  run_in_container 0 true
}

_selftest_libs()     { run_in_container 0 /opt/vvd/lib/selftest.sh libs; }
_selftest_display()  { run_in_container 0 /opt/vvd/lib/selftest.sh display; }
_selftest_env()      { run_in_container 0 /opt/vvd/lib/selftest.sh env; }
_selftest_version()  { run_in_container 0 /opt/vvd/lib/selftest.sh version; }
_selftest_tcl()      { run_in_container 0 /opt/vvd/lib/selftest.sh tcl; }
_selftest_license()  { run_in_container 0 /opt/vvd/lib/selftest.sh license; }
_selftest_sim()      { run_in_container 0 /opt/vvd/lib/selftest.sh sim; }
_selftest_synth()    { run_in_container 0 /opt/vvd/lib/selftest.sh synth; }

_selftest_identity() {
  local probe="$VVD_PROJECT_ROOT/$VVD_BUILD_DIR/.vvd-identity-probe"
  mkdir -p "$(dirname "$probe")"
  rm -f "$probe"
  run_in_container 0 /opt/vvd/lib/selftest.sh identity || return 1
  [ "${VVD_DRY_RUN:-0}" -eq 1 ] && return 0
  [ -f "$probe" ] || { log_error "the container did not create $probe"; return 1; }
  local owner; owner="$(stat -c '%u' "$probe")"
  rm -f "$probe"
  if [ "$owner" != "$(id -u)" ]; then
    log_error "files written in /work are owned by uid $owner, not $(id -u)"
    log_error "check VVD_USER_MODE and, for rootless podman, that --userns=keep-id is supported"
    return 1
  fi
  log_ok "files in /work belong to $(id -un)"
}

_selftest_jtag() {
  local kind host port
  # shellcheck disable=SC2034  # `host` is only relevant to the remote branch
  IFS=$'\t' read -r kind host port <<<"$(jtag_parse_mode)"
  case "$kind" in
    none) log_info "JTAG disabled"; return 77 ;;
    usb)
      [ -n "$(jtag_usb_devices)" ] || { log_info "no cable attached"; return 77; }
      run_in_container 0 /opt/vvd/lib/selftest.sh jtag ;;
    remote)
      if [ "$VVD_JTAG_MODE" = "host" ] &&
         ! timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        log_info "no hw_server on 127.0.0.1:$port"
        return 77
      fi
      run_in_container 0 /opt/vvd/lib/selftest.sh jtag ;;
  esac
}
