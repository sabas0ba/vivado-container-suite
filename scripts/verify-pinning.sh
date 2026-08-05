#!/usr/bin/env bash
# Fail if anything this repository depends on is not pinned by digest.
#
# Covers: base images, apt packages, the Vivado installer, CI actions and the
# development tooling.  `vcs doctor` runs this, and so does CI on every push.
set -uo pipefail


ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

fails=0
say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok()   { [ "$QUIET" -eq 1 ] || printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*" >&2; fails=$((fails + 1)); }

# --- 1. container images ----------------------------------------------------
say 'images'
if [ -s "$ROOT/config/images.lock" ]; then
  n=0
  while IFS='|' read -r key ref; do
    case "$key" in ''|\#*) continue ;; esac
    n=$((n + 1))
    case "$ref" in
      *@sha256:[0-9a-f]*) ok "$key pinned by digest" ;;
      *) bad "config/images.lock: '$key' is not digest-pinned: $ref" ;;
    esac
  done <"$ROOT/config/images.lock"
  [ "$n" -gt 0 ] || bad "config/images.lock has no entries"
else
  bad "config/images.lock is missing or empty"
fi

# Every FROM must reference a digest, directly or through an ARG default.
while IFS= read -r line; do
  ref="$(printf '%s' "$line" | awk '{print $2}')"
  # The patterns below match the literal text '${BASE_IMAGE}' in the Dockerfile.
  # shellcheck disable=SC2016
  case "$ref" in
    *@sha256:*) ok "FROM $ref" ;;
    '${BASE_IMAGE}'|'$BASE_IMAGE')
      default="$(grep -E '^ARG BASE_IMAGE=' "$ROOT/docker/Dockerfile" | head -n1 | cut -d= -f2-)"
      case "$default" in
        *@sha256:*) ok "FROM \$BASE_IMAGE (default is digest-pinned)" ;;
        *) bad "docker/Dockerfile: ARG BASE_IMAGE default is not digest-pinned: $default" ;;
      esac ;;
    *)
      # A FROM referring to an earlier stage in the same Dockerfile is fine.
      if grep -qE "^FROM .* AS ${ref}\$" "$ROOT/docker/Dockerfile"; then
        ok "FROM $ref (build stage)"
      else
        bad "docker/Dockerfile: unpinned FROM: $ref"
      fi ;;
  esac
done < <(grep -E '^FROM ' "$ROOT/docker/Dockerfile")

# The ARG default and the lock must agree, or a plain `docker build` would use
# a different base from `vcs build`.
lock_base="$(grep -E '^base\|' "$ROOT/config/images.lock" | head -n1 | cut -d'|' -f2)"
arg_base="$(grep -E '^ARG BASE_IMAGE=' "$ROOT/docker/Dockerfile" | head -n1 | cut -d= -f2-)"
if [ "$lock_base" = "$arg_base" ]; then
  ok "Dockerfile BASE_IMAGE matches images.lock"
else
  bad "Dockerfile BASE_IMAGE ($arg_base) does not match images.lock ($lock_base)"
fi

# --- 2. apt ----------------------------------------------------------------
say 'apt'
snap="$(grep -E '^APT_SNAPSHOT=' "$ROOT/docker/apt-snapshot.lock" | cut -d= -f2)"
if printf '%s' "$snap" | grep -qE '^[0-9]{8}T[0-9]{6}Z$'; then
  ok "archive snapshot pinned: $snap"
else
  bad "docker/apt-snapshot.lock: APT_SNAPSHOT is not a snapshot timestamp: '$snap'"
fi

if [ -s "$ROOT/docker/packages.lock" ]; then
  unpinned="$(grep -vE '^\s*(#|$)' "$ROOT/docker/packages.lock" | grep -vE '^[^=]+=[^=]+' || true)"
  if [ -n "$unpinned" ]; then
    bad "docker/packages.lock has entries without a version: $(printf '%s' "$unpinned" | tr '\n' ' ')"
  else
    ok "$(grep -cE '^[^#]+=' "$ROOT/docker/packages.lock") apt packages version-pinned"
  fi
  # Everything asked for must actually be locked.
  missing=""
  while read -r p; do
    [ -n "$p" ] || continue
    grep -qE "^${p}=" "$ROOT/docker/packages.lock" || missing="$missing $p"
  done < <(grep -vE '^\s*(#|$)' "$ROOT/docker/packages.list" | tr -d '\r')
  if [ -n "$missing" ]; then
    bad "in packages.list but not packages.lock:$missing (run scripts/lock-apt.sh)"
  else
    ok "packages.list and packages.lock agree"
  fi
else
  bad "docker/packages.lock is missing or empty"
fi

# No ad-hoc installs outside the locked path.  Exactly one exception is
# allowed: the ca-bootstrap stage installs ca-certificates from the live archive
# because snapshot.ubuntu.com is HTTPS-only and the base image has no trust
# store.  Nothing it produces reaches the final image (see the Dockerfile), and
# every .deb it fetches is still GPG-verified by apt.
stray=0
while IFS= read -r line; do
  case "$line" in
    *'pkgs[@]'*)                                    continue ;;   # the packages.lock path
    *'--no-install-recommends ca-certificates'*)    continue ;;
  esac
  bad "docker/Dockerfile installs packages outside the packages.lock path: $line"
  stray=1
done < <(grep -hE '(apt-get|apt) install' "$ROOT/docker/Dockerfile" "$ROOT/docker/install-packages.sh")
[ "$stray" -eq 0 ] && ok "no unpinned apt-get install in the Dockerfile (bar the documented CA bootstrap)"

# The bootstrap trust store must not survive into the image.
# shellcheck disable=SC2016  # a grep pattern matching the literal text
if grep -q 'rm -f "\$BOOTSTRAP_CA"' "$ROOT/docker/install-packages.sh"; then
  ok "the bootstrap CA bundle is removed in the layer that uses it"
else
  bad "docker/install-packages.sh does not delete the bootstrap CA bundle"
fi

# --- 3. downloads -----------------------------------------------------------
say 'downloads'
if grep -rnE 'curl[^|]*\|\s*(ba)?sh|wget[^|]*\|\s*(ba)?sh' \
     "$ROOT/docker" "$ROOT/scripts" "$ROOT/lib" "$ROOT/bin" 2>/dev/null | grep -q .; then
  bad "a script pipes a download straight into a shell"
else
  ok "nothing is piped from the network into a shell"
fi

if [ -s "$ROOT/scripts/tools.lock" ]; then
  while IFS='|' read -r kind name a b c; do
    case "$kind" in ''|\#*) continue ;; esac
    case "$kind" in
      bin|tar)
        if printf '%s' "$b" | grep -qE '^[0-9a-f]{64}$'; then ok "$name pinned by sha256"
        else bad "scripts/tools.lock: $name has no sha256"; fi ;;
      git)
        if printf '%s' "$b" | grep -qE '^[0-9a-f]{40}$'; then ok "$name pinned to commit ${b:0:12}"
        else bad "scripts/tools.lock: $name is not pinned to a commit"; fi ;;
      *) bad "scripts/tools.lock: unknown record type '$kind'" ;;
    esac
    : "$a" "$c"
  done <"$ROOT/scripts/tools.lock"
else
  bad "scripts/tools.lock is missing"
fi

# --- 4. CI actions ----------------------------------------------------------
say 'ci'
wf_dir="$ROOT/.github/workflows"
if [ -d "$wf_dir" ]; then
  found=0
  while IFS= read -r line; do
    found=1
    spec="$(printf '%s' "$line" | sed -E 's/.*uses:[[:space:]]*//; s/[[:space:]]*(#.*)?$//')"
    case "$spec" in
      ./*|docker://*) ok "local/action reference: $spec" ; continue ;;
    esac
    if printf '%s' "$spec" | grep -qE '@[0-9a-f]{40}$'; then
      ok "action pinned: ${spec%@*}"
    else
      bad "$wf_dir: action not pinned to a commit SHA: $spec"
    fi
  done < <(grep -rhE '^\s*-?\s*uses:' "$wf_dir" 2>/dev/null)
  [ "$found" -eq 1 ] || ok "no external actions used"
else
  ok "no workflows to check"
fi

# --- 5. Vivado installer ----------------------------------------------------
say 'vivado'
vlock="$ROOT/config/vivado-versions.lock"
if [ -f "$vlock" ]; then
  n_real=0
  while IFS='|' read -r v f h; do
    case "$v" in ''|\#*) continue ;; esac
    n_real=$((n_real + 1))
    if printf '%s' "$h" | grep -qE '^[0-9a-f]{64}$'; then ok "Vivado $v installer pinned ($f)"
    else bad "config/vivado-versions.lock: $v has no valid sha256"; fi
  done <"$vlock"
  [ "$n_real" -eq 0 ] && ok "no installer digests recorded yet (image-mode builds will refuse to run)"
else
  bad "config/vivado-versions.lock is missing"
fi

if [ "$fails" -gt 0 ]; then
  printf '\nverify-pinning: %d problem(s)\n' "$fails" >&2
  exit 1
fi
say ''
say "verify-pinning: everything is pinned"
exit 0
