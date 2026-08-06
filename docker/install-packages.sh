#!/usr/bin/env bash
# Install the pinned package set from the pinned Ubuntu archive snapshot.
#
# This lives in a script rather than inline in the Dockerfile because the
# `SHELL` instruction is silently ignored when an image is built in OCI format
# (podman/buildah default, and what some CI runners give you behind a `docker`
# shim).  RUN then falls back to /bin/sh, where the bash used below -- arrays,
# mapfile, `set -o pipefail` -- is a syntax error.  An explicit shebang works
# the same way under every builder.
set -euo pipefail

PIN_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTSTRAP_CA="$PIN_DIR/ca-bootstrap.crt"

# shellcheck disable=SC1091  # copied in beside this script at build time
. "$PIN_DIR/apt-snapshot.lock"
: "${APT_SNAPSHOT:?apt-snapshot.lock did not define APT_SNAPSHOT}"
: "${APT_POCKETS:?apt-snapshot.lock did not define APT_POCKETS}"
: "${APT_COMPONENTS:?apt-snapshot.lock did not define APT_COMPONENTS}"

echo "install-packages: snapshot $APT_SNAPSHOT" >&2

cat >/etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT}
Suites: ${APT_POCKETS}
Components: ${APT_COMPONENTS}
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
rm -f /etc/apt/sources.list

# The bootstrap trust store exists only for this step; see the Dockerfile.
cat >/etc/apt/apt.conf.d/99vvd <<EOF
Acquire::Check-Valid-Until "false";
Acquire::Retries "5";
Acquire::https::CaInfo "${BOOTSTRAP_CA}";
EOF

pkgs=()
while IFS= read -r line; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -n "$line" ] && pkgs+=("$line")
done <"$PIN_DIR/packages.lock"

[ "${#pkgs[@]}" -gt 0 ] || { echo "install-packages: packages.lock is empty" >&2; exit 1; }
echo "install-packages: ${#pkgs[@]} packages" >&2

apt-get update
apt-get install -y --no-install-recommends "${pkgs[@]}"

# The pinned ca-certificates package must now own the trust store, so the
# bootstrap copy can go -- in this same layer, so it never ships.
[ -s /etc/ssl/certs/ca-certificates.crt ] ||
  { echo "install-packages: the pinned ca-certificates did not populate the trust store" >&2; exit 1; }
rm -f "$BOOTSTRAP_CA"
cat >/etc/apt/apt.conf.d/99vvd <<'EOF'
Acquire::Check-Valid-Until "false";
Acquire::Retries "5";
EOF

rm -rf /var/lib/apt/lists/*
echo "install-packages: done" >&2
