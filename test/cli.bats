#!/usr/bin/env bats
# CLI surface: help, dispatch, argument validation.

load helper
setup()    { load_helpers; setup_project; }
teardown() { teardown_project; }

@test "help lists every documented command" {
  run "$VVD_REPO_ROOT/bin/vvd" --help
  [ "$status" -eq 0 ]
  for c in build pull synth impl bitstream flow sim program clean tcl run gui shell hw-server doctor selftest info jtag-rules; do
    [[ "$output" == *"$c"* ]] || { echo "missing from help: $c"; false; }
  done
}

@test "no arguments prints usage and exits 2" {
  run "$VVD_REPO_ROOT/bin/vvd"
  [ "$status" -eq 2 ]
}

@test "version is reported without touching the engine" {
  run "$VVD_REPO_ROOT/bin/vvd" version
  [ "$status" -eq 0 ]
  [[ "$output" == vvd\ * ]]
}

@test "an unknown command fails with exit 2" {
  run vvd frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command: frobnicate"* ]]
}

@test "an unknown global option fails with exit 2" {
  run vvd --nope synth
  [ "$status" -eq 2 ]
}

@test "every command in help has an implementation" {
  run "$VVD_REPO_ROOT/bin/vvd" --help
  for c in build pull image synth impl bitstream flow sim program clean tcl run gui shell hw-server doctor selftest info jtag-rules; do
    [ -f "$VVD_REPO_ROOT/lib/cmd/$c.sh" ] || { echo "no lib/cmd/$c.sh"; false; }
    grep -q "^cmd_${c//-/_}()" "$VVD_REPO_ROOT/lib/cmd/$c.sh" || { echo "no cmd function in $c.sh"; false; }
  done
}

@test "each subcommand accepts --help without an engine" {
  export VVD_ENGINE=docker
  for c in build pull image synth impl bitstream flow sim program clean tcl run gui shell hw-server doctor selftest info jtag-rules; do
    run vvd "$c" --help
    [ "$status" -eq 0 ] || { echo "vvd $c --help exited $status: $output"; false; }
  done
}

@test "info reports the resolved configuration" {
  run vvd info
  [ "$status" -eq 0 ]
  [[ "$output" == *"xc7a35tcpg236-1"* ]]
  [[ "$output" == *"2025.2"* ]]
  [[ "$output" == *"nonproject"* ]]
}

@test "image prints the derived reference" {
  run vvd image
  [ "$status" -eq 0 ]
  [ "$output" = "vivado-container-suite:2025.2-base" ]
}

@test "clean refuses an absolute build directory" {
  run vvd --build-dir /etc clean -f
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to clean"* ]]
}

@test "clean removes the build directory" {
  mkdir -p "$PROJECT/build/logs"
  run vvd clean -f
  [ "$status" -eq 0 ]
  [ ! -d "$PROJECT/build" ]
}
