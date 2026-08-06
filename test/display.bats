#!/usr/bin/env bats
# GUI transport selection.

load helper
setup()    { load_helpers; setup_project; }
teardown() { teardown_project; }

@test "display none refuses to launch the GUI, with advice" {
  VVD_DISPLAY_MODE=none run vvd gui
  [ "$status" -ne 0 ]
  [[ "$output" == *"--display xvfb"* ]]
}

@test "batch flows work with no display at all" {
  VVD_DISPLAY_MODE=none run vvd --dry-run synth
  [ "$status" -eq 0 ]
}

@test "xvfb mode asks the entrypoint for a headless X server" {
  VVD_DISPLAY_MODE=xvfb run vvd --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env VVD_DISPLAY_MODE=xvfb
  refute_output_contains "$output" "/tmp/.X11-unix"
}

@test "x11 mode forwards the socket and the DISPLAY" {
  mkdir -p /tmp/.X11-unix
  DISPLAY=:0 VVD_DISPLAY_MODE=x11 run vvd --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env DISPLAY=:0
  assert_arg_pair "$output" --volume "/tmp/.X11-unix:/tmp/.X11-unix:ro"
}

@test "x11 mode fails cleanly when DISPLAY is unset" {
  VVD_DISPLAY_MODE=x11 run vvd --dry-run gui
  [ "$status" -ne 0 ]
  [[ "$output" == *"DISPLAY is unset"* ]]
}

@test "wayland without XWayland is reported, not silently broken" {
  VVD_DISPLAY_MODE=wayland WAYLAND_DISPLAY=wayland-0 run vvd --dry-run gui
  [ "$status" -ne 0 ]
  [[ "$output" == *"XWayland"* ]]
}

@test "wayland with XWayland behaves as x11" {
  mkdir -p /tmp/.X11-unix
  VVD_DISPLAY_MODE=wayland WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 \
    run vvd --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env DISPLAY=:0
}

@test "auto picks x11 when a display is present" {
  mkdir -p /tmp/.X11-unix
  DISPLAY=:0 VVD_DISPLAY_MODE=auto run vvd --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env VVD_DISPLAY_MODE=x11
}

@test "auto picks none on a headless host" {
  VVD_DISPLAY_MODE=auto run vvd --dry-run synth
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env VVD_DISPLAY_MODE=none
}

@test "software rendering is the default; --gpu opts into /dev/dri" {
  mkdir -p /tmp/.X11-unix
  DISPLAY=:0 VVD_DISPLAY_MODE=x11 run vvd --dry-run gui
  assert_arg_pair "$output" --env LIBGL_ALWAYS_SOFTWARE=1

  if [ -d /dev/dri ]; then
    DISPLAY=:0 VVD_DISPLAY_MODE=x11 run vvd --gpu --dry-run gui
    assert_arg_pair "$output" --device /dev/dri
  fi
}

@test "gui opens a named checkpoint through open.tcl" {
  mkdir -p /tmp/.X11-unix
  : >"$PROJECT/build_post_route.dcp"
  DISPLAY=:0 VVD_DISPLAY_MODE=x11 run vvd --dry-run gui build_post_route.dcp
  [ "$status" -eq 0 ]
  [[ "$output" == *"/opt/vvd/tcl/open.tcl"* ]]
  [[ "$output" == *"/work/build_post_route.dcp"* ]]
}

@test "an unmountable GUI target is rejected" {
  mkdir -p /tmp/.X11-unix
  : >"$TMP/elsewhere.dcp"
  DISPLAY=:0 VVD_DISPLAY_MODE=x11 run vvd --dry-run gui "$TMP/elsewhere.dcp"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the project root"* ]]
}


# --- transport classification ----------------------------------------------

@test "a socket DISPLAY mounts the X socket and leaves networking alone" {
  mkdir -p /tmp/.X11-unix
  DISPLAY=:0 VVD_DISPLAY_MODE=x11 run vvd --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --volume "/tmp/.X11-unix:/tmp/.X11-unix:ro"
  refute_output_contains "$output" "--network host"
}

@test "an ssh-forwarded TCP DISPLAY switches to host networking" {
  # `ssh -X` leaves sshd listening on the host's 127.0.0.1, which a bridged
  # container cannot reach.
  DISPLAY=localhost:10.0 VVD_DISPLAY_MODE=x11 run vvd --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --network host
  assert_arg_pair "$output" --env DISPLAY=localhost:10.0
  refute_output_contains "$output" "/tmp/.X11-unix"
}

@test "an IPv4 loopback DISPLAY is treated the same way" {
  DISPLAY=127.0.0.1:10.0 VVD_DISPLAY_MODE=x11 run vvd --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --network host
}

@test "a remote X server needs no special networking" {
  DISPLAY=10.20.30.40:0 VVD_DISPLAY_MODE=x11 run vvd --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env DISPLAY=10.20.30.40:0
  refute_output_contains "$output" "--network host"
  refute_output_contains "$output" "/tmp/.X11-unix"
}

@test "host networking makes hw_server reachable on loopback, not the gateway" {
  DISPLAY=localhost:10.0 VVD_DISPLAY_MODE=x11 VVD_JTAG_MODE=host \
    run vvd --dry-run gui
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env "VVD_HW_SERVER_URL=TCP:localhost:3121"
  refute_output_contains "$output" "host-gateway"
}

@test "an explicit conflicting VVD_NETWORK is reported, not silently overridden" {
  DISPLAY=localhost:10.0 VVD_DISPLAY_MODE=x11 VVD_NETWORK=bridge \
    run vvd --dry-run gui
  [[ "$output" == *"needs host networking"* ]]
  assert_arg_pair "$output" --network bridge
}

# --- VNC --------------------------------------------------------------------

@test "--vnc publishes on loopback and selects a headless display" {
  run vvd --dry-run gui --vnc
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env VVD_DISPLAY_MODE=xvfb
  assert_arg_pair "$output" --env VVD_VNC=1
  assert_arg_pair "$output" --publish "127.0.0.1:5901:5900"
}

@test "--vnc generates a password and delivers it through a mounted file" {
  run vvd --dry-run gui --vnc
  [ "$status" -eq 0 ]
  [[ "$output" == *"password: "* ]]
  [[ "$output" == *":/opt/vvd/vnc-password:ro"* ]]
  # The secret must never travel as an environment variable or an argument.
  refute_output_contains "$output" "VVD_VNC_PASSWORD="
}

@test "a caller-supplied VNC password is used and not printed" {
  VVD_VNC_PASSWORD=hunter2 run vvd --dry-run gui --vnc
  [ "$status" -eq 0 ]
  refute_output_contains "$output" "hunter2"
  [[ "$output" == *"from VVD_VNC_PASSWORD"* ]]
}

@test "info --all does not print the VNC password" {
  VVD_VNC_PASSWORD=hunter2 run vvd info --all
  [ "$status" -eq 0 ]
  refute_output_contains "$output" "hunter2"
  [[ "$output" == *"<set, not shown>"* ]]
}

@test "--vnc-port and --vnc-bind are honoured" {
  run vvd --dry-run gui --vnc-port 5999 --vnc-bind 0.0.0.0
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --publish "0.0.0.0:5999:5900"
  [[ "$output" == *"anyone who can reach port"* ]]
}

@test "the VNC password file is removed when the command exits" {
  before="$(ls /tmp/vvd-vnc.* 2>/dev/null | wc -l)"
  run vvd --dry-run gui --vnc
  [ "$status" -eq 0 ]
  after="$(ls /tmp/vvd-vnc.* 2>/dev/null | wc -l)"
  [ "$before" -eq "$after" ]
}

@test "sim --vnc implies a headless GUI" {
  run vvd --dry-run sim --vnc
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env VVD_VNC=1
  assert_arg_pair "$output" --env VVD_DISPLAY_MODE=xvfb
}

@test "the image can actually serve VNC" {
  grep -qx 'x11vnc' "$VVD_REPO_ROOT/docker/packages.list"
  grep -q '^x11vnc=' "$VVD_REPO_ROOT/docker/packages.lock"
  grep -q 'passwdfile' "$VVD_REPO_ROOT/docker/entrypoint.sh"
  # x11vnc must never be started without authentication.
  ! grep -q 'nopw' "$VVD_REPO_ROOT/docker/entrypoint.sh"
}
