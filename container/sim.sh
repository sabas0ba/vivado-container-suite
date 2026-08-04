#!/usr/bin/env bash
# Behavioural simulation with xvlog / xvhdl / xelab / xsim.
#
# Runs inside the container, driven entirely by VCS_* environment variables.
# The standalone compilers are used rather than a Vivado project: they start in
# under a second and produce the same xsim kernel the IDE does.
set -euo pipefail

gui=0
[ "${1:-}" = "--gui" ] && gui=1

log()  { printf 'vcs-sim  ▸ %s\n' "$*" >&2; }
fail() { printf 'vcs-sim  ✗ %s\n' "$*" >&2; exit 1; }

command -v xelab >/dev/null 2>&1 ||
  fail "xelab is not on PATH -- is Vivado available in the container?  Try: vcs doctor"

top="${VCS_SIM_TOP:?VCS_SIM_TOP is not set}"
build="${VCS_BUILD_DIR:-build}"
# The project is always mounted at /work; the indirection exists so the script
# can be exercised by the test suite outside a container.
work="${VCS_CONTAINER_WORK:-/work}"
simdir="$work/$build/sim"
logdir="$work/$build/logs"
mkdir -p "$simdir" "$logdir"

cd "$work"

# --- collect sources -------------------------------------------------------
vlog=()
vhdl=()
collect() { # <array-name> <patterns...>
  local -n _out="$1"; shift
  local pat f
  for pat in "$@"; do
    [ -n "$pat" ] || continue
    local hits=()
    # shellcheck disable=SC2206
    hits=($pat)
    if [ ${#hits[@]} -eq 1 ] && [ ! -e "${hits[0]}" ]; then
      fail "pattern matched no files: $pat  (cwd: $PWD)"
    fi
    for f in "${hits[@]}"; do
      [ -e "$f" ] || continue
      case " ${_out[*]-} " in *" $work/$f "*) continue ;; esac
      _out+=("$work/$f")
    done
  done
}

# shellcheck disable=SC2206,SC2086
collect vlog ${VCS_SIM_SOURCES:-} ${VCS_SOURCES:-} ${VCS_SV_SOURCES:-}
# shellcheck disable=SC2206,SC2086
collect vhdl ${VCS_SIM_VHDL_SOURCES:-} ${VCS_VHDL_SOURCES:-}

[ ${#vlog[@]} -gt 0 ] || [ ${#vhdl[@]} -gt 0 ] ||
  fail "no simulation sources; set VCS_SIM_SOURCES (and/or VCS_SIM_VHDL_SOURCES) in vcs.conf"

# xvlog and friends create xsim.dir next to the invocation; keep it in build/.
cd "$simdir"

if [ ${#vlog[@]} -gt 0 ]; then
  log "xvlog: ${#vlog[@]} file(s)"
  # shellcheck disable=SC2086
  xvlog --sv --relax --nolog ${VCS_SIM_XVLOG_ARGS:-} "${vlog[@]}"
fi
if [ ${#vhdl[@]} -gt 0 ]; then
  log "xvhdl: ${#vhdl[@]} file(s)"
  xvhdl --relax --nolog "${vhdl[@]}"
fi

snapshot="${top}_snap"
elab=(--relax --debug typical --nolog --snapshot "$snapshot" --mt "${VCS_JOBS:-4}")
for lib in ${VCS_SIM_LIBS:-}; do elab+=(-L "$lib"); done
# What post-synthesis and IP-bearing testbenches need.
elab+=(-L unisims_ver -L unimacro_ver -L secureip)

log "xelab: $top"
# shellcheck disable=SC2086
xelab "${elab[@]}" ${VCS_SIM_XELAB_ARGS:-} "$top"

# --- run script ------------------------------------------------------------
runtcl="$simdir/run.tcl"
{
  [ "${VCS_SIM_WAVES:-1}" = "1" ] && printf 'log_wave -recursive *\n'
  if [ -n "${VCS_SIM_TIME:-}" ]; then printf 'run %s\n' "$VCS_SIM_TIME"
  else printf 'run all\n'; fi
  [ "$gui" -eq 0 ] && printf 'quit\n'
} >"$runtcl"

if [ "$gui" -eq 1 ]; then
  log "xsim --gui: $snapshot"
  exec xsim "$snapshot" --gui --tclbatch "$runtcl" --wdb "$top.wdb"
fi

logfile="$logdir/sim.log"
log "xsim: $snapshot"
rc=0
xsim "$snapshot" --tclbatch "$runtcl" --wdb "$top.wdb" --nolog 2>&1 | tee "$logfile" || rc=$?
[ "${PIPESTATUS[0]:-0}" -eq 0 ] || rc="${PIPESTATUS[0]}"

# xsim exits 0 even when a testbench asserts, so the log is the source of truth.
# shellcheck disable=SC2016  # a grep pattern, not a shell expansion
if grep -qE '(^Error|^Fatal|^FATAL_ERROR|\$fatal|Failure:|\*\*\* FAILED|\bASSERTION FAILED\b)' "$logfile"; then
  fail "the testbench reported errors -- see $build/logs/sim.log"
fi
[ "$rc" -eq 0 ] || fail "xsim exited with status $rc"

log "simulation passed; waveform: $build/sim/$top.wdb"
