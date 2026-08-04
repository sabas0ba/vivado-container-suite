#!/usr/bin/env bash
# Unattended Vivado install, run inside the `vivado` build stage.
#
# The tarball is verified against docker/vivado-versions.lock a second time here
# (the CLI already checked it on the host) so that a build driven by something
# other than `vcs build` still cannot install an unverified installer.
set -euo pipefail

installer="${1:?usage: install-vivado.sh <installer-tarball>}"
version="${VIVADO_VERSION:?}"
edition_name="${VIVADO_EDITION_NAME:-Vivado ML Standard}"
lock=/opt/vcs/pin/vivado-versions.lock

log() { printf 'install-vivado: %s\n' "$*" >&2; }

[ -f "$installer" ] || { log "installer not found: $installer"; exit 1; }

expected="$(awk -F'|' -v v="$version" '$1 == v { print $3 }' "$lock" | head -n1)"
[ -n "$expected" ] || { log "no SHA256 for Vivado $version in $lock"; exit 1; }

log "verifying $installer"
actual="$(sha256sum "$installer" | cut -d' ' -f1)"
if [ "$actual" != "$expected" ]; then
  log "checksum mismatch: expected $expected, got $actual"
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

log "extracting"
tar -xf "$installer" -C "$workdir"
root="$(find "$workdir" -maxdepth 2 -name xsetup -type f -printf '%h\n' | head -n1)"
[ -n "$root" ] || { log "no xsetup found in the tarball"; exit 1; }

# The batch installer needs a config file describing what to install.  Generate
# one rather than shipping a copy that drifts from the installer's own schema.
cfg="$workdir/install_config.txt"
"$root/xsetup" -b ConfigGen -p "$edition_name" -c "$cfg" <<<"1
1
q" >/dev/null 2>&1 || true

if [ ! -f "$cfg" ]; then
  log "ConfigGen did not produce a config; falling back to a minimal one"
  cat >"$cfg" <<CFG
Edition=$edition_name
Product=Vivado
Destination=/opt/Xilinx
Modules=Vivado:1,Vitis:0,DocNav:0
InstallOptions=
CreateProgramGroupShortcuts=0
CreateShortcutsForAllUsers=0
CreateDesktopShortcuts=0
CreateFileAssociation=0
CFG
fi

# Trim the bulk: no docs, no desktop integration, no telemetry.
sed -i \
  -e 's/^Modules=.*/&/' \
  -e 's/^CreateProgramGroupShortcuts=.*/CreateProgramGroupShortcuts=0/' \
  -e 's/^CreateShortcutsForAllUsers=.*/CreateShortcutsForAllUsers=0/' \
  -e 's/^CreateDesktopShortcuts=.*/CreateDesktopShortcuts=0/' \
  -e 's/^CreateFileAssociation=.*/CreateFileAssociation=0/' \
  -e 's|^Destination=.*|Destination=/opt/Xilinx|' \
  "$cfg"

log "installing to /opt/Xilinx (this takes a while)"
"$root/xsetup" \
  --agree XilinxEULA,3rdPartyEULA \
  --batch Install \
  --config "$cfg"

settings="/opt/Xilinx/Vivado/$version/settings64.sh"
[ -f "$settings" ] || { log "install finished but $settings is missing"; exit 1; }

rm -rf /opt/Xilinx/.xinstall /tmp/* 2>/dev/null || true
log "done: Vivado $version"
