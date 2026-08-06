#!/usr/bin/env bats
# The in-container scripts, exercised on the host against stub tools.
#
# container/sim.sh does real work -- source collection, deduplication, run-script
# generation and pass/fail adjudication -- so it gets tested rather than assumed.

load helper

setup() {
  load_helpers
  setup_project

  WORK="$TMP/work"
  mkdir -p "$WORK/rtl" "$WORK/sim"
  cat >"$WORK/rtl/dut.v" <<'EOF'
module dut(input clk, output reg q); always @(posedge clk) q <= ~q; endmodule
EOF
  cat >"$WORK/sim/tb.v" <<'EOF'
module tb; reg clk = 0; wire q; dut u(clk, q); initial #10 $finish; endmodule
EOF

  # Stub compilers that record their argv and let the test dictate the outcome.
  STUB="$TMP/stub"
  mkdir -p "$STUB"
  for t in xvlog xvhdl xelab; do
    cat >"$STUB/$t" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >>"$TMP/$t.argv"
exit \${STUB_${t^^}_STATUS:-0}
EOF
    chmod +x "$STUB/$t"
  done
  cat >"$STUB/xsim" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >>"$TMP/xsim.argv"
printf '%s\n' "\${STUB_XSIM_OUTPUT:-tb: PASS}"
exit \${STUB_XSIM_STATUS:-0}
EOF
  chmod +x "$STUB/xsim"

  export VVD_CONTAINER_WORK="$WORK"
  export VVD_BUILD_DIR=out
  export VVD_JOBS=2
}
teardown() { teardown_project; }

run_sim() {
  PATH="$STUB:$PATH" \
  VVD_SIM_TOP="${VVD_SIM_TOP:-tb}" \
    run "$VVD_REPO_ROOT/container/sim.sh" "$@"
}

@test "sources are collected, prefixed and deduplicated" {
  VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" VVD_SV_SOURCES="rtl/*.v" run_sim
  [ "$status" -eq 0 ]
  argv="$(cat "$TMP/xvlog.argv")"
  [[ "$argv" == *"$WORK/sim/tb.v"* ]]
  [[ "$argv" == *"$WORK/rtl/dut.v"* ]]
  # rtl/dut.v appears in two variables but must be compiled once.
  [ "$(grep -c "rtl/dut.v" <<<"$argv")" -eq 1 ]
}

@test "a pattern that matches nothing is a hard error" {
  VVD_SIM_SOURCES="sim/nope*.v" run_sim
  [ "$status" -ne 0 ]
  [[ "$output" == *"matched no files"* ]]
}

@test "no sources at all is a hard error naming the key to set" {
  VVD_SIM_SOURCES="" VVD_SOURCES="" VVD_SV_SOURCES="" VVD_VHDL_SOURCES="" run_sim
  [ "$status" -ne 0 ]
  [[ "$output" == *"VVD_SIM_SOURCES"* ]]
}

@test "VHDL sources go to xvhdl, not xvlog" {
  cat >"$WORK/sim/tb.vhd" <<'EOF'
entity tb is end entity;
EOF
  VVD_SIM_SOURCES="sim/tb.v" VVD_SIM_VHDL_SOURCES="sim/*.vhd" run_sim
  [ "$status" -eq 0 ]
  [[ "$(cat "$TMP/xvhdl.argv")" == *"tb.vhd"* ]]
  [[ "$(cat "$TMP/xvlog.argv")" != *"tb.vhd"* ]]
}

@test "the elaboration snapshot is named after the top" {
  VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" run_sim
  [ "$status" -eq 0 ]
  [[ "$(cat "$TMP/xelab.argv")" == *"tb_snap"* ]]
  [[ "$(cat "$TMP/xelab.argv")" == *"unisims_ver"* ]]
}

@test "VVD_SIM_TIME becomes a bounded run, otherwise run all" {
  VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" run_sim
  grep -qx 'run all' "$WORK/out/sim/run.tcl"

  VVD_SIM_TIME=250ns VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" run_sim
  grep -qx 'run 250ns' "$WORK/out/sim/run.tcl"
}

@test "waves are recorded by default and suppressed on request" {
  VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" run_sim
  grep -q 'log_wave' "$WORK/out/sim/run.tcl"

  VVD_SIM_WAVES=0 VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" run_sim
  ! grep -q 'log_wave' "$WORK/out/sim/run.tcl"
}

@test "a testbench assertion fails the run even though xsim exits 0" {
  STUB_XSIM_OUTPUT='*** FAILED: counter mismatch' \
  VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" run_sim
  [ "$status" -ne 0 ]
  [[ "$output" == *"testbench reported errors"* ]]
}

@test "a Verilog \$fatal is detected" {
  STUB_XSIM_OUTPUT='$fatal called at time 100 ns' \
  VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" run_sim
  [ "$status" -ne 0 ]
}

@test "a VHDL Failure severity is detected" {
  STUB_XSIM_OUTPUT='Failure: assertion violation' \
  VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" run_sim
  [ "$status" -ne 0 ]
}

@test "a non-zero xsim exit status fails the run" {
  STUB_XSIM_STATUS=4 VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" run_sim
  [ "$status" -ne 0 ]
  [[ "$output" == *"exited with status 4"* ]]
}

@test "a compile error fails the run" {
  STUB_XVLOG_STATUS=1 VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" run_sim
  [ "$status" -ne 0 ]
}

@test "a clean run passes and leaves a log" {
  VVD_SIM_SOURCES="sim/*.v" VVD_SOURCES="rtl/*.v" run_sim
  [ "$status" -eq 0 ]
  [[ "$output" == *"simulation passed"* ]]
  [ -s "$WORK/out/logs/sim.log" ]
}

@test "sim.sh explains itself when Vivado is absent" {
  VVD_SIM_TOP=tb VVD_SIM_SOURCES="sim/*.v" \
    run env PATH=/usr/bin:/bin "$VVD_REPO_ROOT/container/sim.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"vvd doctor"* ]]
}

@test "the smoke fixtures the selftest relies on exist and are self-checking" {
  [ -f "$VVD_REPO_ROOT/container/smoke/smoke.v" ]
  [ -f "$VVD_REPO_ROOT/container/smoke/tb_smoke.v" ]
  grep -q '\*\*\* FAILED' "$VVD_REPO_ROOT/container/smoke/tb_smoke.v"
  grep -q 'vvd-smoke: PASS' "$VVD_REPO_ROOT/container/smoke/tb_smoke.v"
  grep -q 'vvd-smoke: PASS' "$VVD_REPO_ROOT/container/selftest.sh"
}

@test "the example testbench is self-checking too" {
  grep -q '\*\*\* FAILED' "$VVD_REPO_ROOT/examples/blinky/sim/tb_blinky.v"
}
