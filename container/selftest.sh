#!/usr/bin/env bash
# In-container selftest stages.  Driven by `vcs selftest`.
#
# Exit codes:  0 pass, 77 skipped (a precondition is absent), anything else fail.
set -uo pipefail

stage="${1:?usage: selftest.sh <stage>}"

log()  { printf 'selftest ▸ %s\n' "$*" >&2; }
fail() { printf 'selftest ✗ %s\n' "$*" >&2; exit 1; }
skip() { printf 'selftest - %s\n' "$*" >&2; exit 77; }

build="${VCS_BUILD_DIR:-build}"
work="/work/$build/selftest"
smoke=/opt/vcs/lib/smoke

need_vivado() {
  [ "${VCS_VIVADO_READY:-0}" = "1" ] && return 0
  # CI builds the base image without Vivado in it, and there is real value in
  # still exercising everything that does not need the tools.  Set
  # VCS_SELFTEST_REQUIRE_VIVADO=0 to turn those stages into skips.
  { [ "${VCS_SELFTEST_REQUIRE_VIVADO:-1}" = "0" ] || [ "${VCS_VIVADO_MODE:-mount}" = "none" ]; } &&
    skip "Vivado is not present in this container"
  fail "Vivado is not available in the container (settings64.sh was not found)"
}

# A compatibility symlink (libtinfo.so.5 -> libtinfo.so.6) carries the SONAME of
# its target, so ldconfig never lists it under its own name even though the
# loader resolves it from the standard search path.  Check both.
have_lib() {
  ldconfig -p 2>/dev/null | grep -q "$1" && return 0
  local d
  for d in /lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu /lib64 /usr/lib; do
    [ -e "$d/$1" ] && return 0
  done
  return 1
}

prepare_smoke() {
  mkdir -p "$work"
  cp -f "$smoke"/*.v "$work/"
}

case "$stage" in

  libs)
    # Vivado dlopen()s most of its GUI stack late, so a missing library only
    # surfaces when a specific tool starts.  Check them up front instead.
    missing=()
    for lib in libtinfo.so.5 libtinfo.so.6 libncurses.so.5 \
               libX11.so.6 libXtst.so.6 libXrender.so.1 libXi.so.6 \
               libxcb-xinerama.so.0 libxcb-cursor.so.0 libxcb-icccm.so.4 \
               libxkbcommon-x11.so.0 libfontconfig.so.1 libfreetype.so.6 \
               libGL.so.1 libEGL.so.1 libGLU.so.1 \
               libnss3.so libnspr4.so libasound.so.2 libdbus-1.so.3 \
               libgtk-3.so.0 libusb-1.0.so.0; do
      have_lib "$lib" || missing+=("$lib")
    done
    [ ${#missing[@]} -eq 0 ] || fail "missing shared libraries: ${missing[*]}"
    log "every expected shared library resolves"
    command -v tclsh >/dev/null 2>&1 || fail "tclsh is missing from the image"
    log "tclsh: $(command -v tclsh)"
    ;;

  display)
    case "${VCS_DISPLAY_MODE:-none}" in
      none) skip "no display requested" ;;
    esac
    [ -n "${DISPLAY:-}" ] || fail "VCS_DISPLAY_MODE=${VCS_DISPLAY_MODE} but DISPLAY is unset"
    command -v xdpyinfo >/dev/null 2>&1 || fail "xdpyinfo is missing from the image"
    xdpyinfo >/dev/null 2>&1 || fail "cannot open the X display $DISPLAY"
    log "X display $DISPLAY is usable ($(xdpyinfo | awk '/dimensions:/ {print $2}'))"
    ;;

  env)
    need_vivado
    missing=()
    for t in vivado xelab xsim xvlog xvhdl hw_server; do
      command -v "$t" >/dev/null 2>&1 || missing+=("$t")
    done
    [ ${#missing[@]} -eq 0 ] || fail "not on PATH: ${missing[*]}"
    log "vivado:    $(command -v vivado)"
    log "xsim:      $(command -v xsim)"
    log "hw_server: $(command -v hw_server)"
    ;;

  version)
    need_vivado
    out="$(vivado -version 2>&1 | head -n3)" || fail "vivado -version failed:
$out"
    printf '%s\n' "$out" >&2
    want="${VCS_VIVADO_VERSION:-}"
    if [ -n "$want" ] && ! printf '%s' "$out" | grep -q "$want"; then
      fail "expected Vivado $want, but the tool reports:
$out"
    fi
    ;;

  tcl)
    need_vivado
    mkdir -p "$work"
    probe="$work/tcl-probe.txt"
    rm -f "$probe"
    script="$work/tcl-probe.tcl"
    cat >"$script" <<TCL
set fh [open "$probe" w]
puts \$fh "version: [version -short]"
puts \$fh "parts: [llength [get_parts]]"
puts \$fh "pwd: [pwd]"
close \$fh
puts "selftest tcl: [version -short], [llength [get_parts]] parts visible"
TCL
    vivado -mode batch -nojournal -nolog -notrace -source "$script" >&2 ||
      fail "vivado -mode batch exited non-zero"
    [ -s "$probe" ] || fail "the Tcl script did not write $probe (is /work writable?)"
    cat "$probe" >&2
    ;;

  identity)
    mkdir -p "/work/$build"
    probe="/work/$build/.vcs-identity-probe"
    printf 'uid=%s gid=%s\n' "$(id -u)" "$(id -g)" >"$probe" ||
      fail "cannot write $probe"
    log "wrote $probe as uid=$(id -u)"
    ;;

  license)
    if [ -z "${XILINXD_LICENSE_FILE:-}" ]; then
      skip "no XILINXD_LICENSE_FILE set"
    fi
    case "$XILINXD_LICENSE_FILE" in
      *@*)
        port="${XILINXD_LICENSE_FILE%%@*}"
        host="${XILINXD_LICENSE_FILE#*@}"
        host="${host%%:*}"
        (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null ||
          fail "cannot reach the license server $host:$port from inside the container"
        log "license server $host:$port reachable" ;;
      *)
        [ -r "$XILINXD_LICENSE_FILE" ] ||
          fail "$XILINXD_LICENSE_FILE is not readable inside the container"
        grep -q 'INCREMENT' "$XILINXD_LICENSE_FILE" 2>/dev/null ||
          log "warning: the license file contains no INCREMENT line"
        log "license file readable: $XILINXD_LICENSE_FILE" ;;
    esac
    log "note: the 'synth' stage is the end-to-end proof that the license works"
    ;;

  sim)
    need_vivado
    prepare_smoke
    log "simulating the smoke testbench"
    VCS_SIM_TOP=tb_smoke \
    VCS_SIM_SOURCES="$build/selftest/tb_smoke.v $build/selftest/smoke.v" \
    VCS_SIM_VHDL_SOURCES='' \
    VCS_SOURCES='' VCS_SV_SOURCES='' VCS_VHDL_SOURCES='' \
    VCS_SIM_TIME='' VCS_SIM_WAVES=0 \
    VCS_BUILD_DIR="$build/selftest/out" \
      /opt/vcs/lib/sim.sh || fail "the smoke simulation failed"
    grep -q 'vcs-smoke: PASS' "/work/$build/selftest/out/logs/sim.log" ||
      fail "the testbench did not report PASS"
    ;;

  synth)
    need_vivado
    prepare_smoke
    part="${VCS_SELFTEST_PART:-${VCS_PART:-xc7a35tcpg236-1}}"
    log "synthesising the smoke design for $part"
    VCS_TOP=smoke \
    VCS_PART="$part" \
    VCS_BOARD_PART='' \
    VCS_SOURCES="$build/selftest/smoke.v" \
    VCS_SV_SOURCES='' VCS_VHDL_SOURCES='' VCS_CONSTRAINTS='' VCS_IP='' VCS_BD='' \
    VCS_XPR='' VCS_FLOW_MODE=nonproject \
    VCS_PRE_TCL='' VCS_POST_TCL='' \
    VCS_BUILD_DIR="$build/selftest/out" \
      vivado -mode batch -nojournal -notrace \
             -log "/work/$build/selftest/out/logs/synth.log" \
             -source "$VCS_CONTAINER_TCL/flow.tcl" -tclargs synth >&2 ||
      fail "synthesis of the smoke design failed -- most often this is a missing or expired license"
    [ -f "/work/$build/selftest/out/post_synth.dcp" ] ||
      fail "synthesis reported success but produced no checkpoint"
    log "checkpoint written"
    ;;

  jtag)
    need_vivado
    url="${VCS_HW_SERVER_URL:-}"
    [ -n "$url" ] || skip "JTAG is disabled"
    mkdir -p "$work"
    script="$work/jtag-probe.tcl"
    cat >"$script" <<TCL
open_hw_manager
if {[catch {connect_hw_server -url "$url" -allow_non_jtag} err]} {
    puts stderr "selftest ✗ cannot reach hw_server at $url: \$err"
    exit 1
}
set t [get_hw_targets -quiet]
puts "selftest ▸ hw_server ok, targets: \$t"
if {[llength \$t] == 0} { puts "selftest - no JTAG target attached"; disconnect_hw_server; exit 77 }
current_hw_target [lindex \$t 0]
open_hw_target
puts "selftest ▸ devices: [get_hw_devices]"
close_hw_target
disconnect_hw_server
TCL
    vivado -mode batch -nojournal -nolog -notrace -source "$script" >&2
    rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 77 ] || fail "the JTAG probe failed (exit $rc)"
    exit "$rc"
    ;;

  *) fail "unknown stage: $stage" ;;
esac

log "stage '$stage' passed"
