# shellcheck shell=bash
# Project discovery and layered configuration.

VCS_CONF_BASENAME="vcs.conf"
VCS_LOCAL_CONF_BASENAME="vcs.local.conf"

# Keys that may be set from a config file.  Anything else is rejected so a typo
# fails loudly instead of being silently ignored.
_vcs_known_keys() {
  grep -oE '^VCS_[A-Z0-9_]+' "$VCS_ROOT/config/vcs.defaults.conf" | sort -u
}

# find_project_root [start] -- walk up looking for vcs.conf; fall back to $PWD.
find_project_root() {
  local d="${1:-$PWD}"
  d="$(abspath "$d")"
  while [ "$d" != "/" ]; do
    [ -f "$d/$VCS_CONF_BASENAME" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  [ -f "/$VCS_CONF_BASENAME" ] && { printf '/'; return 0; }
  return 1
}

# _vcs_source_conf <file> -- read KEY=VALUE lines, validating key names.
# Values may be quoted; no command substitution is performed.
_vcs_source_conf() {
  local file="$1" line key value lineno=0
  [ -f "$file" ] || return 0
  log_debug "config: reading $file"
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ ! "$line" =~ ^[[:space:]]*(VCS_[A-Z0-9_]+)[[:space:]]*=(.*)$ ]]; then
      die "$file:$lineno: not a VCS_<KEY>=<value> assignment: $line"
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    # strip surrounding quotes and trailing whitespace
    value="${value%"${value##*[![:space:]]}"}"
    case "$value" in
      \"*\") value="${value:1:${#value}-2}" ;;
      \'*\') value="${value:1:${#value}-2}" ;;
    esac
    if ! printf '%s\n' "$VCS_KNOWN_KEYS" | grep -qx "$key"; then
      die "$file:$lineno: unknown configuration key: $key"
    fi
    printf -v "$key" '%s' "$value"
    export "${key?}"
  done <"$file"
}

# load_config <project_root> [explicit_conf]
load_config() {
  local root="$1" explicit="${2:-}"
  VCS_KNOWN_KEYS="$(_vcs_known_keys)"

  # 1. snapshot VCS_* that came from the real environment -- they outrank files
  local envsnap key
  envsnap="$(mktemp)"
  while read -r key; do
    if [ -n "${!key+x}" ]; then printf '%s=%s\n' "$key" "${!key}" >>"$envsnap"; fi
  done <<<"$VCS_KNOWN_KEYS"

  _vcs_source_conf "$VCS_ROOT/config/vcs.defaults.conf"
  if [ -n "$explicit" ]; then
    require_file "$explicit" "config file"
    _vcs_source_conf "$explicit"
  else
    _vcs_source_conf "$root/$VCS_CONF_BASENAME"
    _vcs_source_conf "$root/$VCS_LOCAL_CONF_BASENAME"
  fi

  # 4. environment wins over files
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue
    printf -v "$key" '%s' "$value"
    export "${key?}"
  done <"$envsnap"
  rm -f "$envsnap"

  VCS_PROJECT_ROOT="$root"
  export VCS_PROJECT_ROOT
}

# derive_config -- fill in values that depend on other values.  Called after
# CLI flags have been applied.
derive_config() {
  : "${VCS_PROJECT_NAME:=$(basename "$VCS_PROJECT_ROOT")}"

  if [ -z "$VCS_IMAGE_TAG" ]; then
    VCS_IMAGE_TAG="$VCS_VIVADO_VERSION"
    # mount and none both run the base image; only `image` mode has Vivado in it.
    case "$VCS_VIVADO_MODE" in
      mount|none) VCS_IMAGE_TAG="${VCS_VIVADO_VERSION}-base" ;;
    esac
  fi
  : "${VCS_IMAGE:=${VCS_IMAGE_NAME}:${VCS_IMAGE_TAG}}"

  if [ -z "$VCS_CACHE_DIR" ]; then
    VCS_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/vivado-container-suite"
  fi
  VCS_CACHE_DIR="$(abspath "$VCS_CACHE_DIR")"

  if [ -z "$VCS_JOBS" ]; then
    VCS_JOBS="$( (nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4) )"
  fi

  VCS_VIVADO_SETTINGS="$VCS_CONTAINER_XILINX_ROOT/$VCS_VIVADO_EDITION/$VCS_VIVADO_VERSION/settings64.sh"

  export VCS_PROJECT_NAME VCS_IMAGE VCS_IMAGE_TAG VCS_CACHE_DIR VCS_JOBS VCS_VIVADO_SETTINGS
}

# config_dump -- human readable summary (used by `vcs info` and `vcs doctor`).
config_dump() {
  local key value
  while read -r key; do
    value="${!key}"
    # Never echo a secret just because someone asked for the configuration.
    case "$key" in
      *PASSWORD*|*SECRET*|*TOKEN*) [ -n "$value" ] && value='<set, not shown>' ;;
    esac
    printf '%-28s %s\n' "$key" "$value"
  done <<<"$(_vcs_known_keys)"
}
