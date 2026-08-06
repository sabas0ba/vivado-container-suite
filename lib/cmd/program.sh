# shellcheck shell=bash
# vvd program -- push a bitstream onto the device over JTAG.

cmd_program() {
  local bit="" target="" probes="" list_only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --bit)     bit="${2:?--bit needs a file}"; shift 2 ;;
      --target)  target="${2:?--target needs a device pattern, e.g. xc7a35t_0}"; shift 2 ;;
      --probes)  probes="${2:?--probes needs an .ltx file}"; shift 2 ;;
      --list)    list_only=1; shift ;;
      -h|--help)
        cat <<'H'
vvd program [options]

  --bit FILE      Bitstream to download (default: <build>/<top>.bit)
  --target PAT    Device to program when the scan chain has more than one
  --probes FILE   Debug probes (.ltx) to associate with the device
  --list          Only enumerate the scan chain, program nothing

Transport is chosen by --jtag / VVD_JTAG_MODE:
  host            hw_server runs on the host (default; no device passthrough)
  usb             USB cable handed to the container, hw_server runs inside it
  remote:H[:P]    a named hw_server, e.g. a lab machine
See docs/07-jtag.md.
H
        return 0 ;;
      *) die_usage "vvd program: unexpected argument: $1" ;;
    esac
  done

  local kind
  kind="$(jtag_parse_mode | cut -f1)"
  [ "$kind" = "none" ] && die "VVD_JTAG_MODE is 'none'; pick --jtag host, --jtag usb or --jtag remote:HOST"

  if [ -z "$bit" ]; then
    require_project_settings VVD_TOP
    bit="$VVD_BUILD_DIR/$VVD_TOP.bit"
  fi

  # Reject a path that would not be visible inside the container.
  local host_bit="$VVD_PROJECT_ROOT/$bit"
  case "$bit" in /*) host_bit="$bit" ;; esac
  if [ "$list_only" -eq 0 ] && [ "${VVD_DRY_RUN:-0}" -eq 0 ]; then
    [ -f "$host_bit" ] || die "bitstream not found: $host_bit
  Build one first:  vvd bitstream"
  fi

  local cbit="$bit"
  case "$bit" in
    /*) cbit="${bit/#$VVD_PROJECT_ROOT/$VVD_CONTAINER_WORK}"
        [ "$cbit" = "$bit" ] && die "bitstream is outside the project root and therefore not visible in the container: $bit" ;;
    *)  cbit="$VVD_CONTAINER_WORK/$bit" ;;
  esac

  VVD_PROGRAM_BIT="$cbit"
  VVD_PROGRAM_TARGET="$target"
  VVD_PROGRAM_PROBES="$probes"
  VVD_PROGRAM_LIST="$list_only"
  export VVD_PROGRAM_BIT VVD_PROGRAM_TARGET VVD_PROGRAM_PROBES VVD_PROGRAM_LIST

  VVD_EXTRA_ENV="$VVD_EXTRA_ENV VVD_PROGRAM_BIT VVD_PROGRAM_TARGET VVD_PROGRAM_PROBES VVD_PROGRAM_LIST"

  log_info "jtag: $(jtag_describe)"
  if [ "$list_only" -eq 1 ]; then
    log_info "enumerating the scan chain"
  else
    log_info "programming $cbit"
  fi
  vivado_batch "$VVD_CONTAINER_TCL/program.tcl" program
}
