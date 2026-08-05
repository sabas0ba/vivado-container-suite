#!/usr/bin/env bats
# License injection: the license must reach the container without ever being
# baked into an image or copied into the project.

load helper
setup()    { load_helpers; setup_project; }
teardown() { teardown_project; }

@test "a floating server is passed as an environment variable only" {
  VCS_LICENSE="2100@lic.example.com" run vcs --dry-run synth
  assert_arg_pair "$output" --env "XILINXD_LICENSE_FILE=2100@lic.example.com"
  refute_output_contains "$output" "/opt/vcs/license"
}

@test "several floating servers are passed verbatim" {
  VCS_LICENSE="2100@a.example.com:2100@b.example.com" run vcs --dry-run synth
  assert_arg_pair "$output" --env "XILINXD_LICENSE_FILE=2100@a.example.com:2100@b.example.com"
}

@test "a node-locked file is bind-mounted read-only" {
  printf 'INCREMENT x\n' >"$TMP/Xilinx.lic"
  VCS_LICENSE="$TMP/Xilinx.lic" run vcs --dry-run synth
  assert_arg_pair "$output" --volume "$TMP/Xilinx.lic:/opt/vcs/license/Xilinx.lic:ro"
  assert_arg_pair "$output" --env "XILINXD_LICENSE_FILE=/opt/vcs/license/Xilinx.lic"
}

@test "a license directory is bind-mounted read-only" {
  mkdir -p "$TMP/licenses"
  VCS_LICENSE="dir:$TMP/licenses" run vcs --dry-run synth
  assert_arg_pair "$output" --volume "$TMP/licenses:/opt/vcs/license:ro"
  assert_arg_pair "$output" --env "XILINXD_LICENSE_FILE=/opt/vcs/license"
}

@test "a missing license file fails before the container starts" {
  VCS_LICENSE="$TMP/absent.lic" run vcs --dry-run synth
  [ "$status" -ne 0 ]
  [[ "$output" == *"license file not found"* ]]
}

@test "a malformed spec is rejected" {
  VCS_LICENSE="not-a-license-spec" run vcs --dry-run synth
  [ "$status" -ne 0 ]
  [[ "$output" == *"unrecognised VCS_LICENSE spec"* ]]
}

@test "XILINXD_LICENSE_FILE from the host environment is picked up" {
  unset VCS_LICENSE
  XILINXD_LICENSE_FILE="2100@from-env" run vcs --dry-run synth
  assert_arg_pair "$output" --env "XILINXD_LICENSE_FILE=2100@from-env"
}

@test "VCS_LICENSE outranks the host environment" {
  XILINXD_LICENSE_FILE="2100@from-env" VCS_LICENSE="2100@from-config" \
    run vcs --dry-run synth
  assert_arg_pair "$output" --env "XILINXD_LICENSE_FILE=2100@from-config"
  refute_output_contains "$output" "from-env"
}

@test "~/.Xilinx is picked up when present, read-only" {
  unset VCS_LICENSE
  mkdir -p "$HOME/.Xilinx"
  printf 'INCREMENT x\n' >"$HOME/.Xilinx/Xilinx.lic"
  run vcs --dry-run synth
  assert_arg_pair "$output" --volume "$HOME/.Xilinx:/home/vivado/.Xilinx:ro"
}

@test "no license at all is allowed, and mounts nothing" {
  VCS_LICENSE=none run vcs --dry-run synth
  [ "$status" -eq 0 ]
  refute_output_contains "$output" "XILINXD_LICENSE_FILE"
}

@test "the image never carries a license, and the build proves it" {
  # Nothing in the image build may copy license material in...
  run grep -inE '^\s*COPY.*\.lic' "$VCS_REPO_ROOT/docker/Dockerfile"
  [ "$status" -ne 0 ]
  # ...and the last step of the base stage refuses to ship one.
  grep -q 'check-no-license.sh' "$VCS_REPO_ROOT/docker/Dockerfile"
  grep -q 'refusing to ship an image containing a .lic file' \
       "$VCS_REPO_ROOT/docker/check-no-license.sh"
}

@test "the license guard is the last step of the base stage" {
  # Anything added after it would escape the check.
  guard="$(grep -n 'check-no-license.sh' "$VCS_REPO_ROOT/docker/Dockerfile" | tail -1 | cut -d: -f1)"
  stage="$(grep -n '^FROM base AS vivado' "$VCS_REPO_ROOT/docker/Dockerfile" | cut -d: -f1)"
  [ -n "$guard" ] && [ -n "$stage" ]
  run bash -c "sed -n '$((guard + 1)),$((stage - 1))p' '$VCS_REPO_ROOT/docker/Dockerfile' | grep -E '^(COPY|ADD|RUN)'"
  [ "$status" -ne 0 ]
}
