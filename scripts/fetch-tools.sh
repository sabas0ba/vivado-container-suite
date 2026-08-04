#!/usr/bin/env bash
# Fetch the pinned development tooling into .tools/.
#
# Everything comes from scripts/tools.lock and is verified before use: binaries
# and tarballs by SHA256, git checkouts by commit id.  Nothing is piped from the
# network into a shell.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/scripts/tools.lock"
DEST="${VCS_TOOLS_DIR:-$ROOT/.tools}"

log() { printf 'fetch-tools: %s\n' "$*" >&2; }

verify() { # <file> <expected-sha256>
  local actual
  actual="$(sha256sum "$1" | cut -d' ' -f1)"
  [ "$actual" = "$2" ] || {
    rm -f "$1"
    log "CHECKSUM MISMATCH for $1"
    log "  expected $2"
    log "  actual   $actual"
    exit 1
  }
}

mkdir -p "$DEST/bin"

while IFS='|' read -r kind name a b c; do
  case "$kind" in ''|\#*) continue ;; esac

  case "$kind" in
    bin)
      target="$DEST/bin/$name"
      if [ -x "$target" ]; then log "$name: already present"; continue; fi
      log "$name: downloading"
      curl -fsSL --retry 3 --retry-delay 2 -o "$target.tmp" "$a"
      verify "$target.tmp" "$b"
      chmod +x "$target.tmp"; mv "$target.tmp" "$target"
      ;;
    tar)
      target="$DEST/bin/$name"
      if [ -x "$target" ]; then log "$name: already present"; continue; fi
      log "$name: downloading"
      tmp="$(mktemp -d)"
      curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/archive" "$a"
      verify "$tmp/archive" "$b"
      tar -xf "$tmp/archive" -C "$tmp" --strip-components="${c:-0}"
      found="$(find "$tmp" -maxdepth 2 -type f -name "$name" -perm -u+x | head -n1)"
      [ -n "$found" ] || { log "$name not found inside the archive"; exit 1; }
      install -m 0755 "$found" "$target"
      rm -rf "$tmp"
      ;;
    git)
      target="$DEST/$name"
      if [ -d "$target/.git" ] &&
         [ "$(git -C "$target" rev-parse HEAD 2>/dev/null)" = "$b" ]; then
        log "$name: already at $b"; continue
      fi
      log "$name: cloning at $b"
      rm -rf "$target"
      git init -q "$target"
      git -C "$target" remote add origin "$a"
      git -C "$target" fetch -q --depth 1 origin "$b"
      git -C "$target" checkout -q FETCH_HEAD
      actual="$(git -C "$target" rev-parse HEAD)"
      [ "$actual" = "$b" ] || { log "$name: checked out $actual, expected $b"; exit 1; }
      ;;
    *) log "unknown record type: $kind"; exit 1 ;;
  esac
done <"$LOCK"

# bats looks for helper libraries relative to itself.
if [ -d "$DEST/bats-core" ] && [ ! -e "$DEST/bin/bats" ]; then
  ln -sf "../bats-core/bin/bats" "$DEST/bin/bats"
fi

log "tools ready in $DEST/bin"
