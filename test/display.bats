#!/usr/bin/env bats
# GUI transport selection.

load helper
setup()    { load_helpers; setup_project; }
teardown() { teardown_project; }

@test "display none refuses to launch the GUI, with advice" {
  VCS_DISPLAY_MODE=none run vcs gui
  [ "$status" -ne 0 ]
  [[ "$output" == *"--display xvfb"* ]]
}

@test "batch flows work with no display at all" {
  VCS_DISPLAY_MODE=none run vcs --dry-run synth
  [ "$status" -eq 0 ]
}

@test "xvfb mode asks the entrypoint for a headless X server" {
  VCS_DISPLAY_MODE=xvfb run vcs --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env VCS_DISPLAY_MODE=xvfb
  refute_output_contains "$output" "/tmp/.X11-unix"
}

@test "x11 mode forwards the socket and the DISPLAY" {
  mkdir -p /tmp/.X11-unix
  DISPLAY=:0 VCS_DISPLAY_MODE=x11 run vcs --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env DISPLAY=:0
  assert_arg_pair "$output" --volume "/tmp/.X11-unix:/tmp/.X11-unix:ro"
}

@test "x11 mode fails cleanly when DISPLAY is unset" {
  VCS_DISPLAY_MODE=x11 run vcs --dry-run gui
  [ "$status" -ne 0 ]
  [[ "$output" == *"DISPLAY is unset"* ]]
}

@test "wayland without XWayland is reported, not silently broken" {
  VCS_DISPLAY_MODE=wayland WAYLAND_DISPLAY=wayland-0 run vcs --dry-run gui
  [ "$status" -ne 0 ]
  [[ "$output" == *"XWayland"* ]]
}

@test "wayland with XWayland behaves as x11" {
  mkdir -p /tmp/.X11-unix
  VCS_DISPLAY_MODE=wayland WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 \
    run vcs --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env DISPLAY=:0
}

@test "auto picks x11 when a display is present" {
  mkdir -p /tmp/.X11-unix
  DISPLAY=:0 VCS_DISPLAY_MODE=auto run vcs --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env VCS_DISPLAY_MODE=x11
}

@test "auto picks none on a headless host" {
  VCS_DISPLAY_MODE=auto run vcs --dry-run synth
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env VCS_DISPLAY_MODE=none
}

@test "software rendering is the default; --gpu opts into /dev/dri" {
  mkdir -p /tmp/.X11-unix
  DISPLAY=:0 VCS_DISPLAY_MODE=x11 run vcs --dry-run gui
  assert_arg_pair "$output" --env LIBGL_ALWAYS_SOFTWARE=1

  if [ -d /dev/dri ]; then
    DISPLAY=:0 VCS_DISPLAY_MODE=x11 run vcs --gpu --dry-run gui
    assert_arg_pair "$output" --device /dev/dri
  fi
}

@test "gui opens a named checkpoint through open.tcl" {
  mkdir -p /tmp/.X11-unix
  : >"$PROJECT/build_post_route.dcp"
  DISPLAY=:0 VCS_DISPLAY_MODE=x11 run vcs --dry-run gui build_post_route.dcp
  [ "$status" -eq 0 ]
  [[ "$output" == *"/opt/vcs/tcl/open.tcl"* ]]
  [[ "$output" == *"/work/build_post_route.dcp"* ]]
}

@test "an unmountable GUI target is rejected" {
  mkdir -p /tmp/.X11-unix
  : >"$TMP/elsewhere.dcp"
  DISPLAY=:0 VCS_DISPLAY_MODE=x11 run vcs --dry-run gui "$TMP/elsewhere.dcp"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the project root"* ]]
}
