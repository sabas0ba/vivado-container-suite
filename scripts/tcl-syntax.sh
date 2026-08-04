#!/usr/bin/env bash
# Syntax-check the Tcl layer.
#
# Uses the host's tclsh if there is one; otherwise falls back to the tclsh in
# the built base image, which is why `tcl` is in docker/packages.list.  If
# neither is available the check is skipped rather than silently passing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# `info complete` rejects unbalanced braces, brackets and quotes without needing
# Vivado's command set, which is the class of error a lint can actually catch
# here.  Semantic checking of Vivado commands happens in `vcs selftest`.
# shellcheck disable=SC2016  # this is Tcl, not shell
CHECK='
foreach f $argv {
    set fh [open $f r]; set body [read $fh]; close $fh
    if {![info complete $body]} {
        puts stderr "tcl-syntax: unbalanced braces/brackets/quotes in $f"
        exit 1
    }
    puts "tcl-syntax: ok $f"
}
'

files=("$ROOT"/tcl/*.tcl)
[ -e "${files[0]}" ] || { echo "tcl-syntax: no Tcl files"; exit 0; }

if command -v tclsh >/dev/null 2>&1; then
  exec tclsh <(printf '%s' "$CHECK") "${files[@]}"
fi

engine=""
for e in podman docker; do command -v "$e" >/dev/null 2>&1 && { engine="$e"; break; }; done
image="${VCS_IMAGE:-vivado-container-suite:${VCS_VIVADO_VERSION:-2025.2}-base}"

if [ -n "$engine" ] && "$engine" image inspect "$image" >/dev/null 2>&1; then
  rel=()
  for f in "${files[@]}"; do rel+=("/opt/vcs/tcl/$(basename "$f")"); done
  printf '%s' "$CHECK" >"$ROOT/.tcl-syntax.tcl"
  trap 'rm -f "$ROOT/.tcl-syntax.tcl"' EXIT
  exec "$engine" run --rm \
    --entrypoint tclsh \
    -v "$ROOT/tcl:/opt/vcs/tcl:ro" \
    -v "$ROOT/.tcl-syntax.tcl:/tmp/check.tcl:ro" \
    "$image" /tmp/check.tcl "${rel[@]}"
fi

echo "tcl-syntax: SKIPPED (no tclsh on the host and no $image to borrow one from)" >&2
exit 0
