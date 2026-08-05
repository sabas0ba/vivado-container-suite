#!/usr/bin/env bats
# Configuration discovery and precedence.

load helper
setup()    { load_helpers; setup_project; }
teardown() { teardown_project; }

@test "defaults apply when vcs.conf is silent" {
  run vcs info
  [ "$status" -eq 0 ]
  [[ "$output" == *"2025.2"* ]]
}

@test "vcs.conf overrides the built-in defaults" {
  echo 'VCS_VIVADO_VERSION=2024.2' >>"$PROJECT/vcs.conf"
  mkdir -p "$XILINX/Vivado/2024.2"; : >"$XILINX/Vivado/2024.2/settings64.sh"
  run vcs info
  [[ "$output" == *"2024.2"* ]]
}

@test "vcs.local.conf overrides vcs.conf" {
  echo 'VCS_TOP=from_conf' >>"$PROJECT/vcs.conf"
  echo 'VCS_TOP=from_local' >>"$PROJECT/vcs.local.conf"
  run vcs info
  [[ "$output" == *"from_local"* ]]
}

@test "the environment overrides both config files" {
  echo 'VCS_TOP=from_conf' >>"$PROJECT/vcs.conf"
  echo 'VCS_TOP=from_local' >>"$PROJECT/vcs.local.conf"
  VCS_TOP=from_env run vcs info
  [[ "$output" == *"from_env"* ]]
}

@test "a command line flag overrides the environment" {
  VCS_TOP=from_env run vcs --top from_flag info
  [[ "$output" == *"from_flag"* ]]
}

@test "an unknown key in vcs.conf is a hard error" {
  echo 'VCS_TYPO_HERE=1' >>"$PROJECT/vcs.conf"
  run vcs info
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown configuration key: VCS_TYPO_HERE"* ]]
}

@test "a malformed line in vcs.conf is a hard error" {
  echo 'this is not an assignment' >>"$PROJECT/vcs.conf"
  run vcs info
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a VCS_<KEY>=<value> assignment"* ]]
}

@test "quoted values are unquoted exactly once" {
  echo 'VCS_TOP="quoted_top"' >>"$PROJECT/vcs.conf"
  run vcs info
  [[ "$output" == *"quoted_top"* ]]
  [[ "$output" != *'"quoted_top"'* ]]
}

@test "config values are not evaluated as shell" {
  echo 'VCS_TOP=$(touch '"$TMP"'/pwned)' >>"$PROJECT/vcs.conf"
  run vcs info
  [ ! -e "$TMP/pwned" ]
}

@test "the project root is found by walking up from a subdirectory" {
  mkdir -p "$PROJECT/rtl/deep/deeper"
  cd "$PROJECT/rtl/deep/deeper"
  run "$VCS_REPO_ROOT/bin/vcs" info
  [ "$status" -eq 0 ]
  [[ "$output" == *"$PROJECT"* ]]
}

@test "--config selects an explicit file" {
  cat >"$TMP/other.conf" <<'EOF'
VCS_TOP=other_top
VCS_PART=xc7z020clg400-1
EOF
  run "$VCS_REPO_ROOT/bin/vcs" --config "$TMP/other.conf" info
  [ "$status" -eq 0 ]
  [[ "$output" == *"other_top"* ]]
}

@test "info --all lists every known key" {
  run vcs info --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"VCS_HW_SERVER_PORT"* ]]
  [[ "$output" == *"VCS_EXTRA_MOUNTS"* ]]
}

@test "every key used by the libraries has a default" {
  # A key referenced in lib/ but absent from the defaults file would be unset
  # under `set -u` at run time.
  missing=""
  for k in $(grep -rhoE '\$\{?VCS_[A-Z0-9_]+' "$VCS_REPO_ROOT/lib" \
             | sed -E 's/^\$\{?//' | sort -u); do
    case "$k" in
      VCS_ROOT|VCS_VERSION|VCS_COMMAND|VCS_DRY_RUN|VCS_GPU|VCS_LOG_LEVEL|\
      VCS_PROJECT_ROOT|VCS_IMAGE|VCS_CACHE_DIR|VCS_JOBS|VCS_PROJECT_NAME|\
      VCS_IMAGE_TAG|VCS_VIVADO_SETTINGS|VCS_KNOWN_KEYS|VCS_TEMP_FILES|\
      VCS_XAUTH_FILE|VCS_VNC_FILE|VCS_ENGINE_BIN|VCS_ENGINE_KIND|VCS_ENGINE_ROOTLESS|\
      VCS_CONTAINER_WORK|VCS_CONTAINER_XILINX_ROOT|VCS_CONTAINER_HOME|\
      VCS_CONTAINER_LICENSE_DIR|VCS_CONTAINER_TCL|VCS_CONF_BASENAME|\
      VCS_LOCAL_CONF_BASENAME|VCS_JTAG_VIDS|VCS_JTAG_USB_ALL|VCS_UDEV_PATH|\
      VCS_DOCTOR_FAIL|VCS_DOCTOR_WARN|VCS_SIM_WAVES|VCS_PROGRAM_BIT|\
      VCS_PROGRAM_TARGET|VCS_PROGRAM_PROBES|VCS_PROGRAM_LIST|VCS_XVFB_GEOMETRY|\
      VCS_SELFTEST_PART|VCS_HW_SERVER_URL|VCS_START_HW_SERVER|VCS_UID|VCS_GID|\
      VCS_PRIVDROPPED|VCS_VIVADO_READY|VCS_REQUIRE_VIVADO|VCS_TOOLS_DIR|\
      VCS_RUN_ARGV) continue ;;
    esac
    grep -qE "^${k}=" "$VCS_REPO_ROOT/config/vcs.defaults.conf" || missing="$missing $k"
  done
  [ -z "$missing" ] || { echo "keys with no default:$missing"; false; }
}
