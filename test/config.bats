#!/usr/bin/env bats
# Configuration discovery and precedence.

load helper
setup()    { load_helpers; setup_project; }
teardown() { teardown_project; }

@test "defaults apply when vvd.conf is silent" {
  run vvd info
  [ "$status" -eq 0 ]
  [[ "$output" == *"2025.2"* ]]
}

@test "vvd.conf overrides the built-in defaults" {
  echo 'VVD_VIVADO_VERSION=2024.2' >>"$PROJECT/vvd.conf"
  mkdir -p "$XILINX/Vivado/2024.2"; : >"$XILINX/Vivado/2024.2/settings64.sh"
  run vvd info
  [[ "$output" == *"2024.2"* ]]
}

@test "vvd.local.conf overrides vvd.conf" {
  echo 'VVD_TOP=from_conf' >>"$PROJECT/vvd.conf"
  echo 'VVD_TOP=from_local' >>"$PROJECT/vvd.local.conf"
  run vvd info
  [[ "$output" == *"from_local"* ]]
}

@test "the environment overrides both config files" {
  echo 'VVD_TOP=from_conf' >>"$PROJECT/vvd.conf"
  echo 'VVD_TOP=from_local' >>"$PROJECT/vvd.local.conf"
  VVD_TOP=from_env run vvd info
  [[ "$output" == *"from_env"* ]]
}

@test "a command line flag overrides the environment" {
  VVD_TOP=from_env run vvd --top from_flag info
  [[ "$output" == *"from_flag"* ]]
}

@test "an unknown key in vvd.conf is a hard error" {
  echo 'VVD_TYPO_HERE=1' >>"$PROJECT/vvd.conf"
  run vvd info
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown configuration key: VVD_TYPO_HERE"* ]]
}

@test "a malformed line in vvd.conf is a hard error" {
  echo 'this is not an assignment' >>"$PROJECT/vvd.conf"
  run vvd info
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a VVD_<KEY>=<value> assignment"* ]]
}

@test "quoted values are unquoted exactly once" {
  echo 'VVD_TOP="quoted_top"' >>"$PROJECT/vvd.conf"
  run vvd info
  [[ "$output" == *"quoted_top"* ]]
  [[ "$output" != *'"quoted_top"'* ]]
}

@test "config values are not evaluated as shell" {
  echo 'VVD_TOP=$(touch '"$TMP"'/pwned)' >>"$PROJECT/vvd.conf"
  run vvd info
  [ ! -e "$TMP/pwned" ]
}

@test "the project root is found by walking up from a subdirectory" {
  mkdir -p "$PROJECT/rtl/deep/deeper"
  cd "$PROJECT/rtl/deep/deeper"
  run "$VVD_REPO_ROOT/bin/vvd" info
  [ "$status" -eq 0 ]
  [[ "$output" == *"$PROJECT"* ]]
}

@test "--config selects an explicit file" {
  cat >"$TMP/other.conf" <<'EOF'
VVD_TOP=other_top
VVD_PART=xc7z020clg400-1
EOF
  run "$VVD_REPO_ROOT/bin/vvd" --config "$TMP/other.conf" info
  [ "$status" -eq 0 ]
  [[ "$output" == *"other_top"* ]]
}

@test "info --all lists every known key" {
  run vvd info --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"VVD_HW_SERVER_PORT"* ]]
  [[ "$output" == *"VVD_EXTRA_MOUNTS"* ]]
}

@test "every key used by the libraries has a default" {
  # A key referenced in lib/ but absent from the defaults file would be unset
  # under `set -u` at run time.
  missing=""
  for k in $(grep -rhoE '\$\{?VVD_[A-Z0-9_]+' "$VVD_REPO_ROOT/lib" \
             | sed -E 's/^\$\{?//' | sort -u); do
    case "$k" in
      VVD_ROOT|VVD_VERSION|VVD_COMMAND|VVD_DRY_RUN|VVD_GPU|VVD_LOG_LEVEL|\
      VVD_PROJECT_ROOT|VVD_IMAGE|VVD_CACHE_DIR|VVD_JOBS|VVD_PROJECT_NAME|\
      VVD_IMAGE_TAG|VVD_VIVADO_SETTINGS|VVD_KNOWN_KEYS|VVD_TEMP_FILES|\
      VVD_XAUTH_FILE|VVD_VNC_FILE|VVD_ENGINE_BIN|VVD_ENGINE_KIND|VVD_ENGINE_ROOTLESS|\
      VVD_CONTAINER_WORK|VVD_CONTAINER_XILINX_ROOT|VVD_CONTAINER_HOME|\
      VVD_CONTAINER_LICENSE_DIR|VVD_CONTAINER_TCL|VVD_CONF_BASENAME|\
      VVD_LOCAL_CONF_BASENAME|VVD_JTAG_VIDS|VVD_JTAG_USB_ALL|VVD_UDEV_PATH|\
      VVD_DOCTOR_FAIL|VVD_DOCTOR_WARN|VVD_SIM_WAVES|VVD_PROGRAM_BIT|\
      VVD_PROGRAM_TARGET|VVD_PROGRAM_PROBES|VVD_PROGRAM_LIST|VVD_XVFB_GEOMETRY|\
      VVD_SELFTEST_PART|VVD_HW_SERVER_URL|VVD_START_HW_SERVER|VVD_UID|VVD_GID|\
      VVD_PRIVDROPPED|VVD_VIVADO_READY|VVD_REQUIRE_VIVADO|VVD_TOOLS_DIR|\
      VVD_RUN_ARGV) continue ;;
    esac
    grep -qE "^${k}=" "$VVD_REPO_ROOT/config/vvd.defaults.conf" || missing="$missing $k"
  done
  [ -z "$missing" ] || { echo "keys with no default:$missing"; false; }
}
