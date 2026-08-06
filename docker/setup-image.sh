#!/usr/bin/env bash
# Everything the image needs beyond its packages: compatibility links, locale,
# the default account and the mount points.
#
# In a script rather than inline in the Dockerfile for the reason explained at
# the top of install-packages.sh: `SHELL` is ignored under OCI image format.
set -euo pipefail

echo "setup-image: compatibility links" >&2
# Vivado's Tcl and a few IP flows still look for the SONAME-5 curses libraries
# that Ubuntu dropped after 20.04.  The ABI is compatible for the symbols they
# use, so a link is the supported workaround.
for pair in "libtinfo.so.6:libtinfo.so.5" \
            "libncurses.so.6:libncurses.so.5" \
            "libncursesw.so.6:libncursesw.so.5"; do
  src="${pair%%:*}"; dst="${pair##*:}"
  if [ -e "/lib/x86_64-linux-gnu/$src" ] && [ ! -e "/lib/x86_64-linux-gnu/$dst" ]; then
    ln -s "$src" "/lib/x86_64-linux-gnu/$dst"
  fi
done
ldconfig

echo "setup-image: locale and accounts" >&2
locale-gen en_US.UTF-8
groupadd --gid 1500 vivado
useradd --uid 1500 --gid 1500 --create-home --home-dir /home/vivado --shell /bin/bash vivado
groupadd --system --gid 1501 plugdev 2>/dev/null || true
usermod -aG plugdev vivado

mkdir -p /work /opt/Xilinx /opt/vvd/license /opt/vvd/tcl /opt/vvd/lib
chown vivado:vivado /work /home/vivado


echo "setup-image: done" >&2
