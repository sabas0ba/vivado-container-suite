#!/usr/bin/env bash
# In-container half of `vvd doctor --deep`.
set -uo pipefail

fails=0
ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }
note() { printf '        %s\n' "$*"; }

# A compatibility symlink (libtinfo.so.5 -> libtinfo.so.6) carries the SONAME of
# its target, so ldconfig never lists it under its own name even though the
# loader resolves it from the standard search path.  Check both.
have_lib() {
  ldconfig -p 2>/dev/null | grep -q "$1" && return 0
  local d
  for d in /lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu /lib64 /usr/lib; do
    [ -e "$d/$1" ] && return 0
  done
  return 1
}

printf '  --- inside the container ---\n'

ok "uid=$(id -u) gid=$(id -g) ($(id -un 2>/dev/null || echo '<no passwd entry>'))"
[ "$(id -u)" -eq 0 ] && note "running as root; files written to /work will be root-owned on the host"

if [ -w /work ]; then ok "/work is writable"; else bad "/work is not writable"; fi
if [ -w "$HOME" ]; then ok "\$HOME ($HOME) is writable"; else bad "\$HOME ($HOME) is not writable"; fi

if [ "${VVD_VIVADO_READY:-0}" = "1" ]; then
  ok "Vivado environment sourced"
else
  bad "settings64.sh was not found; Vivado is not on PATH"
  note "mount mode: check VVD_XILINX_ROOT / VVD_VIVADO_VERSION on the host"
fi

for t in vivado xelab xsim xvlog hw_server xsct; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t: $(command -v "$t")"
  else bad "$t not on PATH"; fi
done

# Shared libraries Vivado dlopen()s late; a missing one only shows up when the
# GUI or a specific IP flow starts, which is exactly the failure this catches.
missing=()
for lib in libtinfo.so.5 libXtst.so.6 libxcb-xinerama.so.0 libxcb-cursor.so.0 \
           libGL.so.1 libEGL.so.1 libnss3.so libasound.so.2 libusb-1.0.so.0; do
  have_lib "$lib" || missing+=("$lib")
done
if [ ${#missing[@]} -eq 0 ]; then ok "runtime libraries present"
else bad "missing runtime libraries: ${missing[*]}"; fi

case "${VVD_DISPLAY_MODE:-none}" in
  x11|xvfb)
    if [ -n "${DISPLAY:-}" ] && command -v xdpyinfo >/dev/null 2>&1 &&
       xdpyinfo >/dev/null 2>&1; then
      ok "X display $DISPLAY reachable"
    else
      bad "X display ${DISPLAY:-<unset>} is not reachable"
      note "x11: check the socket mount and the xauth cookie"
    fi ;;
  *) ok "no display requested" ;;
esac

if [ -n "${XILINXD_LICENSE_FILE:-}" ]; then
  ok "XILINXD_LICENSE_FILE=$XILINXD_LICENSE_FILE"
  case "$XILINXD_LICENSE_FILE" in
    *@*) ;;
    *) [ -r "$XILINXD_LICENSE_FILE" ] || bad "the license path is not readable in the container" ;;
  esac
else
  printf '  warn  no XILINXD_LICENSE_FILE; licensed features will fail\n'
fi

if [ -n "${VVD_HW_SERVER_URL:-}" ]; then
  hp="${VVD_HW_SERVER_URL#TCP:}"
  h="${hp%%:*}"; p="${hp##*:}"
  if (exec 3<>"/dev/tcp/$h/$p") 2>/dev/null; then ok "hw_server reachable at $h:$p"
  else printf '  warn  hw_server not reachable at %s:%s\n' "$h" "$p"; fi
fi

printf '  --- %s ---\n' "$( [ "$fails" -eq 0 ] && echo 'all container checks passed' || echo "$fails container check(s) failed" )"
exit "$( [ "$fails" -eq 0 ] && echo 0 || echo 1 )"
