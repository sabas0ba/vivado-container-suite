# shellcheck shell=bash
# Common setup for the bats suite.

VCS_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VCS_REPO_ROOT="$(cd "$VCS_TEST_DIR/.." && pwd)"
export VCS_TEST_DIR VCS_REPO_ROOT

load_helpers() {
  local tools="$VCS_REPO_ROOT/.tools"
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
  cat >"$PROJECT/vcs.conf" <<EOF
VCS_TOP=top
VCS_PART=xc7a35tcpg236-1
VCS_SOURCES=rtl/*.v
VCS_SIM_TOP=tb_top
VCS_SIM_SOURCES=sim/*.v
EOF

  export PATH="$VCS_TEST_DIR/fixtures/bin:$PATH"
  export VCS_ENGINE=docker
  export VCS_XILINX_ROOT="$XILINX"
  export VCS_CACHE_DIR="$TMP/cache"
  export VCS_DISPLAY_MODE=none
  export VCS_JTAG_MODE=none
  export VCS_LICENSE=none
  export VCS_TEST_ARGV="$TMP/argv"
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
vcs() {
  "$VCS_REPO_ROOT/bin/vcs" -C "$PROJECT" "$@"
}

# The last recorded engine argv, one argument per line.
argv_lines() { cat "$VCS_TEST_ARGV" 2>/dev/null; }

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
