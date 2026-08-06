# shellcheck shell=bash
# Logging, error handling and small shared helpers.

VVD_LOG_LEVEL="${VVD_LOG_LEVEL:-info}"

_vvd_use_color() {
  [ -t 2 ] && [ "${NO_COLOR:-}" = "" ] && [ "${TERM:-dumb}" != "dumb" ]
}

_vvd_paint() { # <sgr> <text>
  if _vvd_use_color; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}

_vvd_level_num() {
  case "$1" in
    debug) echo 10 ;; info) echo 20 ;; warn) echo 30 ;; error) echo 40 ;; *) echo 20 ;;
  esac
}

_vvd_emit() { # <level> <sgr> <label> <message...>
  local level="$1" sgr="$2" label="$3"; shift 3
  [ "$(_vvd_level_num "$level")" -ge "$(_vvd_level_num "$VVD_LOG_LEVEL")" ] || return 0
  printf '%s %s\n' "$(_vvd_paint "$sgr" "$label")" "$*" >&2
}

log_debug() { _vvd_emit debug '2'    'vvd  ·' "$@"; }
log_info()  { _vvd_emit info  '1;34' 'vvd  ▸' "$@"; }
log_warn()  { _vvd_emit warn  '1;33' 'vvd  !' "$@"; }
log_error() { _vvd_emit error '1;31' 'vvd  ✗' "$@"; }
log_ok()    { _vvd_emit info  '1;32' 'vvd  ✓' "$@"; }

die() { log_error "$@"; exit 1; }

# die_usage <message> -- user error; exit 2 so scripts can distinguish it from
# a genuine tool failure.
die_usage() { log_error "$@"; log_error "run 'vvd help' for usage"; exit 2; }

have() { command -v "$1" >/dev/null 2>&1; }

# require_file <path> <what>
require_file() {
  [ -e "$1" ] || die "$2 not found: $1"
}

# quote_cmd <argv...> -- render an argv as a copy-pasteable shell command.
quote_cmd() {
  local out='' a
  for a in "$@"; do
    if [[ "$a" =~ ^[A-Za-z0-9_@%+=:,./-]+$ ]]; then out+="$a "; else out+="$(printf '%q' "$a") "; fi
  done
  printf '%s' "${out% }"
}

# abspath <path> -- resolve without requiring the target to exist.
abspath() {
  local p="$1"
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  local out='' part
  local IFS='/'
  for part in $p; do
    case "$part" in
      ''|'.') ;;
      '..') out="${out%/*}" ;;
      *) out="$out/$part" ;;
    esac
  done
  printf '%s' "${out:-/}"
}
