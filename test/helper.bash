# shellcheck shell=bash
# Common setup for the bats suite.

VVD_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VVD_REPO_ROOT="$(cd "$VVD_TEST_DIR/.." && pwd)"
export VVD_TEST_DIR VVD_REPO_ROOT

load_helpers() {
  local tools="$VVD_REPO_ROOT/.tools"
  if [ -d "$tools/bats-support" ]; then load "$tools/bats-support/load"; fi
  if [ -d "$tools/bats-assert" ];  then load "$tools/bats-assert/load"; fi
}

# A scratch project plus a fake Vivado installation, so the CLI's existence
# checks pass without a 100 GB install.
setup_project() {
  TMP="$(mktemp -d)"
  export TMP
  PROJECT="$TMP/proj"
  XILINX="$TMP/tools/Xilinx"
  mkdir -p "$PROJECT/rtl" "$PROJECT/sim" "$XILINX/Vivado/2025.2"
  : >"$XILINX/Vivado/2025.2/settings64.sh"
  : >"$PROJECT/rtl/top.v"
  cat >"$PROJECT/vvd.conf" <<EOF
VVD_TOP=top
VVD_PART=xc7a35tcpg236-1
VVD_SOURCES=rtl/*.v
VVD_SIM_TOP=tb_top
VVD_SIM_SOURCES=sim/*.v
EOF

  export PATH="$VVD_TEST_DIR/fixtures/bin:$PATH"
  export VVD_ENGINE=docker
  export VVD_XILINX_ROOT="$XILINX"
  export VVD_CACHE_DIR="$TMP/cache"
  export VVD_DISPLAY_MODE=none
  export VVD_JTAG_MODE=none
  export VVD_LICENSE=none
  export VVD_TEST_ARGV="$TMP/argv"
  # Do not let the developer's own environment leak into the assertions.
  unset XILINXD_LICENSE_FILE DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR
  export HOME="$TMP/home"
  mkdir -p "$HOME"
}

teardown_project() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
  return 0
}

# Run the CLI against the scratch project.
vvd() {
  "$VVD_REPO_ROOT/bin/vvd" -C "$PROJECT" "$@"
}

# The last recorded engine argv, one argument per line.
argv_lines() { cat "$VVD_TEST_ARGV" 2>/dev/null; }

# Mirror the CLI's own rendering, so assertions compare like with like.
shellish() { # <word>
  if [[ "$1" =~ ^[A-Za-z0-9_@%+=:,./-]+$ ]]; then printf '%s' "$1"
  else printf '%q' "$1"; fi
}

# assert that the dry-run output contains "<flag> <value>" as adjacent tokens
assert_arg_pair() { # <output> <flag> <value>
  local out="$1" flag="$2" value="$3" needle
  needle="$(shellish "$flag") $(shellish "$value")"
  printf '%s' "$out" | grep -qF -- "$needle" || {
    printf 'expected %s in:\n%s\n' "$needle" "$out" >&2
    return 1
  }
}

refute_output_contains() { # <output> <needle>
  local out="$1" needle="$2"
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    printf 'did not expect "%s" in:\n%s\n' "$needle" "$out" >&2
    return 1
  fi
}
