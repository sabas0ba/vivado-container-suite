#!/usr/bin/env bats
# The container command the CLI assembles: mounts, identity, resources.

load helper
setup()    { load_helpers; setup_project; }
teardown() { teardown_project; }

@test "dry-run prints a command and starts nothing" {
  run vcs --dry-run synth
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker run"* ]]
  # The engine was probed, but never asked to start anything.
  run grep -qx run "$VCS_TEST_ARGV"
  [ "$status" -ne 0 ]
}

@test "the project is mounted read-write at /work" {
  run vcs --dry-run synth
  assert_arg_pair "$output" --volume "$PROJECT:/work:rw"
}

@test "the Vivado installation is mounted read-only" {
  run vcs --dry-run synth
  assert_arg_pair "$output" --volume "$XILINX:/opt/Xilinx:ro"
}

@test "the cache directory becomes the container HOME" {
  run vcs --dry-run synth
  assert_arg_pair "$output" --volume "$TMP/cache:/home/vivado:rw"
  assert_arg_pair "$output" --env HOME=/home/vivado
}

@test "the suite's Tcl library is mounted read-only" {
  run vcs --dry-run synth
  assert_arg_pair "$output" --volume "$VCS_REPO_ROOT/tcl:/opt/vcs/tcl:ro"
}

@test "image mode mounts no Vivado tree" {
  run vcs --dry-run --image custom:tag synth
  VCS_VIVADO_MODE=image run vcs --dry-run synth
  [ "$status" -eq 0 ]
  refute_output_contains "$output" ":/opt/Xilinx:ro"
}

@test "mount mode fails clearly when the requested version is absent" {
  run vcs --vivado 2023.1 --dry-run synth
  [ "$status" -ne 0 ]
  [[ "$output" == *"Vivado 2023.1 not found"* ]]
}

@test "mount mode fails clearly when the Vivado root is absent" {
  VCS_XILINX_ROOT="$TMP/nope" run vcs --dry-run synth
  [ "$status" -ne 0 ]
  [[ "$output" == *"VCS_XILINX_ROOT does not exist"* ]]
}

@test "the invoking uid and gid are handed to the entrypoint" {
  run vcs --dry-run synth
  assert_arg_pair "$output" --env "VCS_UID=$(id -u)"
  assert_arg_pair "$output" --env "VCS_GID=$(id -g)"
}

@test "VCS_USER_MODE=root skips the identity mapping" {
  VCS_USER_MODE=root run vcs --dry-run synth
  refute_output_contains "$output" "VCS_UID="
}

@test "/dev/shm is enlarged for place and route" {
  run vcs --dry-run synth
  assert_arg_pair "$output" --shm-size 1g
}

@test "resource limits are passed through when configured" {
  VCS_MEMORY=16g VCS_CPUS=8 run vcs --dry-run synth
  assert_arg_pair "$output" --memory 16g
  assert_arg_pair "$output" --cpus 8
}

@test "extra mounts are honoured" {
  mkdir -p "$TMP/iprepo"
  VCS_EXTRA_MOUNTS="$TMP/iprepo:/opt/iprepo:ro" run vcs --dry-run synth
  assert_arg_pair "$output" --volume "$TMP/iprepo:/opt/iprepo:ro"
}

@test "an extra mount with a missing source fails" {
  VCS_EXTRA_MOUNTS="$TMP/absent:/opt/x:ro" run vcs --dry-run synth
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "project settings reach the container as environment variables" {
  run vcs --dry-run synth
  assert_arg_pair "$output" --env VCS_TOP=top
  assert_arg_pair "$output" --env VCS_PART=xc7a35tcpg236-1
  assert_arg_pair "$output" --env "VCS_SOURCES=rtl/*.v"
}

@test "the synth stage is passed to flow.tcl" {
  run vcs --dry-run synth
  [[ "$output" == *"-source /opt/vcs/tcl/flow.tcl"* ]]
  [[ "$output" == *"-tclargs synth"* ]]
}

@test "flow runs every stage in one Vivado invocation" {
  run vcs --dry-run flow
  [[ "$output" == *"-tclargs all"* ]]
}

@test "synth without a top module fails on the host, before the container" {
  cat >"$PROJECT/vcs.conf" <<'EOF'
VCS_PART=xc7a35tcpg236-1
EOF
  run vcs --dry-run synth
  [ "$status" -ne 0 ]
  [[ "$output" == *"VCS_TOP"* ]]
}

@test "a missing image is reported with the fix" {
  VCS_TEST_IMAGE_MISSING=1 run vcs synth
  [ "$status" -ne 0 ]
  [[ "$output" == *"vcs build"* ]]
}

@test "an unusable engine is reported with the fix" {
  VCS_TEST_ENGINE_BROKEN=1 run vcs synth
  [ "$status" -ne 0 ]
  [[ "$output" == *"vcs doctor"* ]]
}

@test "a failing container run propagates its exit status" {
  VCS_TEST_RUN_STATUS=3 run vcs synth
  [ "$status" -eq 3 ]
}

@test "shell with a command runs it non-interactively" {
  run vcs --dry-run shell vivado -version
  [[ "$output" == *"vivado -version"* ]]
  refute_output_contains "$output" "--interactive"
}

@test "tcl with no script opens an interactive console" {
  run vcs --dry-run tcl
  [[ "$output" == *"--interactive"* ]]
  [[ "$output" == *"vivado -mode tcl"* ]]
}

@test "run rejects a script outside the project" {
  echo 'puts hi' >"$TMP/outside.tcl"
  run vcs run "$TMP/outside.tcl"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the project root"* ]]
}

@test "run maps a project script into the container" {
  mkdir -p "$PROJECT/scripts"
  echo 'puts hi' >"$PROJECT/scripts/hello.tcl"
  run vcs --dry-run run scripts/hello.tcl
  [ "$status" -eq 0 ]
  [[ "$output" == *"-source /work/scripts/hello.tcl"* ]]
}

@test "build passes the pinned base image to the engine" {
  run vcs --dry-run build
  [ "$status" -eq 0 ]
  [[ "$output" == *"--build-arg BASE_IMAGE=ubuntu:24.04@sha256:"* ]]
  [[ "$output" == *"--target base"* ]]
}

@test "build refuses an installer without a recorded digest" {
  : >"$TMP/fake-installer.tar"
  run vcs build --installer "$TMP/fake-installer.tar"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no SHA256 recorded"* ]]
}

@test "pull refuses an unpinned reference" {
  run vcs pull docker.io/example/vivado:latest
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to pull an unpinned reference"* ]]
}
