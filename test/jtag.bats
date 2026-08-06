#!/usr/bin/env bats
# JTAG transports.

load helper
setup() {
  load_helpers
  setup_project
  # A fake lsusb so cable detection is deterministic.
  cat >"$TMP/lsusb" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${VVD_TEST_LSUSB:-}"
EOF
  chmod +x "$TMP/lsusb"
  export PATH="$TMP:$PATH"
}
teardown() { teardown_project; }

@test "host mode reaches hw_server through the engine's host gateway" {
  VVD_JTAG_MODE=host run vvd --dry-run program --bit build/x.bit
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env "VVD_HW_SERVER_URL=TCP:host.docker.internal:3121"
  assert_arg_pair "$output" --add-host "host.docker.internal:host-gateway"
}

@test "host mode passes no USB device through" {
  VVD_JTAG_MODE=host run vvd --dry-run program --bit build/x.bit
  refute_output_contains "$output" "--device /dev/bus/usb"
  refute_output_contains "$output" "--privileged"
}

@test "remote mode targets a named server and port" {
  VVD_JTAG_MODE=remote:lab-01.example.com:3122 \
    run vvd --dry-run program --bit build/x.bit
  assert_arg_pair "$output" --env "VVD_HW_SERVER_URL=TCP:lab-01.example.com:3122"
}

@test "remote mode defaults to the configured port" {
  VVD_JTAG_MODE=remote:lab-01 run vvd --dry-run program --bit build/x.bit
  assert_arg_pair "$output" --env "VVD_HW_SERVER_URL=TCP:lab-01:3121"
}

@test "remote mode without a host is rejected" {
  VVD_JTAG_MODE=remote: run vvd --dry-run program --bit build/x.bit
  [ "$status" -ne 0 ]
  [[ "$output" == *"remote:<host>"* ]]
}

@test "an invalid jtag mode is rejected" {
  VVD_JTAG_MODE=telepathy run vvd --dry-run program --bit build/x.bit
  [ "$status" -ne 0 ]
  [[ "$output" == *"VVD_JTAG_MODE must be"* ]]
}

@test "program refuses when JTAG is disabled" {
  VVD_JTAG_MODE=none run vvd program --bit build/x.bit
  [ "$status" -ne 0 ]
  [[ "$output" == *"--jtag host"* ]]
}

@test "usb mode passes only the matching device nodes" {
  if [ ! -d /dev/bus/usb ]; then skip "no /dev/bus/usb on this host"; fi
  export VVD_TEST_LSUSB="Bus 001 Device 007: ID 0403:6010 Future Technology Devices International, Ltd FT2232C"
  VVD_JTAG_MODE=usb run vvd --dry-run program --bit build/x.bit
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --device "/dev/bus/usb/001/007:/dev/bus/usb/001/007:rwm"
  assert_arg_pair "$output" --env VVD_START_HW_SERVER=1
  refute_output_contains "$output" "--privileged"
}

@test "usb mode ignores devices that are not JTAG cables" {
  if [ ! -d /dev/bus/usb ]; then skip "no /dev/bus/usb on this host"; fi
  export VVD_TEST_LSUSB="Bus 002 Device 003: ID 046d:c52b Logitech, Inc. Unifying Receiver"
  VVD_JTAG_MODE=usb run vvd --dry-run program --bit build/x.bit
  [ "$status" -ne 0 ]
  [[ "$output" == *"no JTAG cable found"* ]]
}

@test "usb mode never emits --privileged" {
  # Mentions in comments are fine; an emitter that prints it is not.
  run grep -rnE "printf.*--privileged|\\+=\\(--privileged" \
      "$VVD_REPO_ROOT/lib" "$VVD_REPO_ROOT/bin"
  [ "$status" -ne 0 ]
}

@test "the whole USB tree is opt-in and warns" {
  if [ ! -d /dev/bus/usb ]; then skip "no /dev/bus/usb on this host"; fi
  VVD_JTAG_MODE=usb VVD_JTAG_USB_ALL=1 run vvd --dry-run program --bit build/x.bit
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --volume "/dev/bus/usb:/dev/bus/usb"
  [[ "$output" == *"passing the whole /dev/bus/usb tree"* ]]
}

@test "program --list enumerates without needing a bitstream" {
  VVD_JTAG_MODE=host run vvd --dry-run program --list
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --env VVD_PROGRAM_LIST=1
}

@test "program rejects a bitstream outside the project" {
  : >"$TMP/outside.bit"
  VVD_JTAG_MODE=host run vvd program --bit "$TMP/outside.bit"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the project root"* ]]
}

@test "program reports a missing bitstream with the fix" {
  VVD_JTAG_MODE=host run vvd program
  [ "$status" -ne 0 ]
  [[ "$output" == *"vvd bitstream"* ]]
}

@test "hw-server publishes on the loopback address by default" {
  if [ ! -d /dev/bus/usb ]; then skip "no /dev/bus/usb on this host"; fi
  export VVD_TEST_LSUSB="Bus 001 Device 007: ID 0403:6010 FTDI"
  run vvd --dry-run hw-server
  [ "$status" -eq 0 ]
  assert_arg_pair "$output" --publish "127.0.0.1:3121:3121"
}

@test "hw-server warns when told to bind every interface" {
  if [ ! -d /dev/bus/usb ]; then skip "no /dev/bus/usb on this host"; fi
  export VVD_TEST_LSUSB="Bus 001 Device 007: ID 0403:6010 FTDI"
  run vvd --dry-run hw-server --bind 0.0.0.0
  [[ "$output" == *"anyone who can reach port"* ]]
}

@test "the udev rules cover the documented vendor IDs" {
  run vvd jtag-rules --print
  [ "$status" -eq 0 ]
  for vid in 03fd 1443 0403; do
    [[ "$output" == *"$vid"* ]] || { echo "vendor $vid missing from the rules"; false; }
  done
  [[ "$output" == *"uaccess"* ]]
  [[ "$output" == *"plugdev"* ]]
}
