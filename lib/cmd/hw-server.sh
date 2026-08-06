# shellcheck shell=bash
# vvd hw-server -- run hw_server inside the container and publish its port.
#
# Useful when the USB cable is attached to the machine running the container and
# other machines (or other containers) should reach it over TCP.

cmd_hw_server() {
  local port="$VVD_HW_SERVER_PORT" bind="127.0.0.1"
  while [ $# -gt 0 ]; do
    case "$1" in
      --port) port="${2:?--port needs a number}"; shift 2 ;;
      --bind) bind="${2:?--bind needs an address}"; shift 2 ;;
      -h|--help)
        cat <<'H'
vvd hw-server [--port N] [--bind ADDR]

  Runs hw_server in the container with the USB cable passed through, and
  publishes it on the host (127.0.0.1 by default -- pass --bind 0.0.0.0 only if
  you really want the whole network to be able to drive your JTAG chain).

  Implies --jtag usb.
H
        return 0 ;;
      *) die_usage "vvd hw-server: unexpected argument: $1" ;;
    esac
  done

  VVD_JTAG_MODE=usb
  VVD_HW_SERVER_PORT="$port"
  export VVD_JTAG_MODE VVD_HW_SERVER_PORT

  if [ "$bind" = "0.0.0.0" ]; then
    log_warn "publishing hw_server on all interfaces; anyone who can reach port $port can reprogram the device"
  fi
  if [ "$VVD_NETWORK" = "host" ]; then
    log_warn "host networking is in effect; hw_server listens on the host's port $port directly"
  else
    VVD_EXTRA_RUN_ARGS="$VVD_EXTRA_RUN_ARGS --publish ${bind}:${port}:${port}"
  fi

  log_info "hw_server on ${bind}:${port} -- connect with: vvd --jtag remote:<host>:${port} program"
  log_info "cables: $(jtag_usb_describe)"
  exec_in_container 1 hw_server -s "TCP::${port}" -d
}
