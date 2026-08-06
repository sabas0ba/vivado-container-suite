#!/usr/bin/env bats
# The Tcl layer: syntax, and the contract it has with the CLI.

load helper
setup()    { load_helpers; setup_project; }
teardown() { teardown_project; }

tclsh_available() { command -v tclsh >/dev/null 2>&1; }

@test "every Tcl file parses" {
  tclsh_available || skip "tclsh is not installed"
  for f in "$VVD_REPO_ROOT"/tcl/*.tcl; do
    # `info complete` on the whole file catches unbalanced braces, brackets and
    # quotes without needing Vivado's command set.
    run tclsh -c "
      set fh [open \"$f\" r]; set body [read \$fh]; close \$fh
      if {![info complete \$body]} { puts stderr {incomplete}; exit 1 }
    "
    [ "$status" -eq 0 ] || { echo "$f does not parse"; false; }
  done
}

@test "lib.tcl defines the helpers the flows use" {
  for proc in vvd::env vvd::info_ vvd::fatal vvd::build_dir vvd::expand \
              vvd::read_sources vvd::part vvd::top vvd::write_reports \
              vvd::check_timing; do
    grep -q "proc ${proc} " "$VVD_REPO_ROOT/tcl/lib.tcl" ||
      { echo "missing proc: $proc"; false; }
  done
}

@test "flow.tcl handles every stage the CLI can ask for" {
  for stage in synth impl bitstream all; do
    grep -qE "^\s+$stage\b" "$VVD_REPO_ROOT/tcl/flow.tcl" ||
      { echo "flow.tcl does not handle stage: $stage"; false; }
  done
}

@test "the Tcl layer reads only environment variables the CLI exports" {
  exported="$(grep -rhoE 'VVD_[A-Z0-9_]+' "$VVD_REPO_ROOT/lib" | sort -u)"
  missing=""
  for k in $(grep -rhoE 'vvd::env (VVD_[A-Z0-9_]+)' "$VVD_REPO_ROOT/tcl" \
             | awk '{print $2}' | sort -u); do
    printf '%s\n' "$exported" | grep -qx "$k" || missing="$missing $k"
  done
  [ -z "$missing" ] || { echo "read by Tcl but never exported:$missing"; false; }
}

@test "timing failure is fatal unless explicitly allowed" {
  grep -q 'VVD_ALLOW_TIMING_VIOLATION' "$VVD_REPO_ROOT/tcl/lib.tcl"
  grep -q 'vvd::fatal "timing not met' "$VVD_REPO_ROOT/tcl/lib.tcl"
}

@test "a source pattern matching nothing is an error, not an empty design" {
  grep -q 'matched no files' "$VVD_REPO_ROOT/tcl/lib.tcl"
  grep -q 'matched no files' "$VVD_REPO_ROOT/container/sim.sh"
}

@test "program.tcl fails loudly when hw_server is unreachable" {
  grep -q 'cannot reach hw_server' "$VVD_REPO_ROOT/tcl/program.tcl"
  grep -q 'no JTAG target is attached' "$VVD_REPO_ROOT/tcl/program.tcl"
}
