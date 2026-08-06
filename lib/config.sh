# shellcheck shell=bash
# Project discovery and layered configuration.

VVD_CONF_BASENAME="vvd.conf"
VVD_LOCAL_CONF_BASENAME="vvd.local.conf"

# Keys that may be set from a config file.  Anything else is rejected so a typo
# fails loudly instead of being silently ignored.
_vvd_known_keys() {
  grep -oE '^VVD_[A-Z0-9_]+' "$VVD_ROOT/config/vvd.defaults.conf" | sort -u
}

# find_project_root [start] -- walk up looking for vvd.conf; fall back to $PWD.
find_project_root() {
  local d="${1:-$PWD}"
  d="$(abspath "$d")"
  while [ "$d" != "/" ]; do
    [ -f "$d/$VVD_CONF_BASENAME" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  [ -f "/$VVD_CONF_BASENAME" ] && { printf '/'; return 0; }
  return 1
}

# _vvd_source_conf <file> -- read KEY=VALUE lines, validating key names.
# Values may be quoted; no command substitution is performed.
_vvd_source_conf() {
  local file="$1" line key value lineno=0
  [ -f "$file" ] || return 0
  log_debug "config: reading $file"
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ ! "$line" =~ ^[[:space:]]*(VVD_[A-Z0-9_]+)[[:space:]]*=(.*)$ ]]; then
      die "$file:$lineno: not a VVD_<KEY>=<value> assignment: $line"
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    # strip surrounding quotes and trailing whitespace
    value="${value%"${value##*[![:space:]]}"}"
    case "$value" in
      \"*\") value="${value:1:${#value}-2}" ;;
      \'*\') value="${value:1:${#value}-2}" ;;
    esac
    if ! printf '%s\n' "$VVD_KNOWN_KEYS" | grep -qx "$key"; then
      die "$file:$lineno: unknown configuration key: $key"
    fi
    printf -v "$key" '%s' "$value"
    export "${key?}"
  done <"$file"
}

# load_config <project_root> [explicit_conf]
load_config() {
  local root="$1" explicit="${2:-}"
  VVD_KNOWN_KEYS="$(_vvd_known_keys)"

  # 1. snapshot VVD_* that came from the real environment -- they outrank files
  local envsnap key
  envsnap="$(mktemp)"
  while read -r key; do
    if [ -n "${!key+x}" ]; then printf '%s=%s\n' "$key" "${!key}" >>"$envsnap"; fi
  done <<<"$VVD_KNOWN_KEYS"

  _vvd_source_conf "$VVD_ROOT/config/vvd.defaults.conf"
  if [ -n "$explicit" ]; then
    require_file "$explicit" "config file"
    _vvd_source_conf "$explicit"
  else
    _vvd_source_conf "$root/$VVD_CONF_BASENAME"
    _vvd_source_conf "$root/$VVD_LOCAL_CONF_BASENAME"
  fi

  # 4. environment wins over files
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue
    printf -v "$key" '%s' "$value"
    export "${key?}"
  done <"$envsnap"
  rm -f "$envsnap"

  VVD_PROJECT_ROOT="$root"
  export VVD_PROJECT_ROOT
}

# derive_config -- fill in values that depend on other values.  Called after
# CLI flags have been applied.
derive_config() {
  : "${VVD_PROJECT_NAME:=$(basename "$VVD_PROJECT_ROOT")}"

  if [ -z "$VVD_IMAGE_TAG" ]; then
    VVD_IMAGE_TAG="$VVD_VIVADO_VERSION"
    # mount and none both run the base image; only `image` mode has Vivado in it.
    case "$VVD_VIVADO_MODE" in
      mount|none) VVD_IMAGE_TAG="${VVD_VIVADO_VERSION}-base" ;;
    esac
  fi
  : "${VVD_IMAGE:=${VVD_IMAGE_NAME}:${VVD_IMAGE_TAG}}"

  if [ -z "$VVD_CACHE_DIR" ]; then
    VVD_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/vivado-container-suite"
  fi
  VVD_CACHE_DIR="$(abspath "$VVD_CACHE_DIR")"

  if [ -z "$VVD_JOBS" ]; then
    VVD_JOBS="$( (nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4) )"
  fi

  VVD_VIVADO_SETTINGS="$VVD_CONTAINER_XILINX_ROOT/$VVD_VIVADO_EDITION/$VVD_VIVADO_VERSION/settings64.sh"

  export VVD_PROJECT_NAME VVD_IMAGE VVD_IMAGE_TAG VVD_CACHE_DIR VVD_JOBS VVD_VIVADO_SETTINGS
}

# config_dump -- human readable summary (used by `vvd info` and `vvd doctor`).
config_dump() {
  local key value
  while read -r key; do
    value="${!key}"
    # Never echo a secret just because someone asked for the configuration.
    case "$key" in
      *PASSWORD*|*SECRET*|*TOKEN*) [ -n "$value" ] && value='<set, not shown>' ;;
    esac
    printf '%-28s %s\n' "$key" "$value"
  done <<<"$(_vvd_known_keys)"
}
