#!/usr/bin/env bats
# CLI surface: help, dispatch, argument validation.

load helper
setup()    { load_helpers; setup_project; }
teardown() { teardown_project; }

@test "help lists every documented command" {
  run "$VCS_REPO_ROOT/bin/vcs" --help
  [ "$status" -eq 0 ]
  for c in build pull synth impl bitstream flow sim program clean tcl run gui shell hw-server doctor selftest info jtag-rules; do
    [[ "$output" == *"$c"* ]] || { echo "missing from help: $c"; false; }
  done
}

@test "no arguments prints usage and exits 2" {
  run "$VCS_REPO_ROOT/bin/vcs"
  [ "$status" -eq 2 ]
}

@test "version is reported without touching the engine" {
  run "$VCS_REPO_ROOT/bin/vcs" version
  [ "$status" -eq 0 ]
  [[ "$output" == vcs\ * ]]
}

@test "an unknown command fails with exit 2" {
  run vcs frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command: frobnicate"* ]]
}

@test "an unknown global option fails with exit 2" {
  run vcs --nope synth
  [ "$status" -eq 2 ]
}

@test "every command in help has an implementation" {
  run "$VCS_REPO_ROOT/bin/vcs" --help
  for c in build pull image synth impl bitstream flow sim program clean tcl run gui shell hw-server doctor selftest info jtag-rules; do
    [ -f "$VCS_REPO_ROOT/lib/cmd/$c.sh" ] || { echo "no lib/cmd/$c.sh"; false; }
    grep -q "^cmd_${c//-/_}()" "$VCS_REPO_ROOT/lib/cmd/$c.sh" || { echo "no cmd function in $c.sh"; false; }
  done
}

@test "each subcommand accepts --help without an engine" {
  export VCS_ENGINE=docker
  for c in build pull image synth impl bitstream flow sim program clean tcl run gui shell hw-server doctor selftest info jtag-rules; do
    run vcs "$c" --help
    [ "$status" -eq 0 ] || { echo "vcs $c --help exited $status: $output"; false; }
  done
}

@test "info reports the resolved configuration" {
  run vcs info
  [ "$status" -eq 0 ]
  [[ "$output" == *"xc7a35tcpg236-1"* ]]
  [[ "$output" == *"2025.2"* ]]
  [[ "$output" == *"nonproject"* ]]
}

@test "image prints the derived reference" {
  run vcs image
  [ "$status" -eq 0 ]
  [ "$output" = "vivado-container-suite:2025.2-base" ]
}

@test "clean refuses an absolute build directory" {
  run vcs --build-dir /etc clean -f
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to clean"* ]]
}

@test "clean removes the build directory" {
  mkdir -p "$PROJECT/build/logs"
  run vcs clean -f
  [ "$status" -eq 0 ]
  [ ! -d "$PROJECT/build" ]
}
