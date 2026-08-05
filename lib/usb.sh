# shellcheck shell=bash
# JTAG plumbing.
#
# Three transports, in decreasing order of preference:
#
#   host          hw_server runs on the HOST; the container only speaks TCP to
#                 it.  No device passthrough, no extra capabilities -- this is
#                 the default and the one to reach for.
#   remote:H:P    same, but an explicitly named host (lab server, CI fixture).
#   usb           the specific USB device nodes for detected cables are passed
#                 in with --device.  Never --privileged, never the whole /dev.

# USB vendor IDs that ship JTAG cables Vivado can drive.
VCS_JTAG_VIDS=(
  "0403"  # FTDI -- Digilent HS1/HS2/HS3, JTAG-SMT2/3, most third-party cables
  "03fd"  # Xilinx -- Platform Cable USB / USB II (DLC9, DLC10)
  "1443"  # Digilent (legacy)
  "1d50"  # OpenMoko-assigned range used by some open cables (e.g. Xvc adapters)
)

jtag_parse_mode() { # -> "kind<TAB>host<TAB>port"
  case "$VCS_JTAG_MODE" in
    none)
      printf 'none\t\t' ;;
    host)
      # Under host networking the container shares the host's loopback, so the
      # gateway alias would miss an hw_server bound to 127.0.0.1.
      if [ "${VCS_NETWORK:-}" = "host" ]; then
        printf 'remote\tlocalhost\t%s' "$VCS_HW_SERVER_PORT"
      else
        printf 'remote\t%s\t%s' "$(engine_host_gateway_name)" "$VCS_HW_SERVER_PORT"
      fi ;;
    usb)
      printf 'usb\tlocalhost\t%s' "$VCS_HW_SERVER_PORT" ;;
    remote:*)
      local rest="${VCS_JTAG_MODE#remote:}" h p
      h="${rest%%:*}"
      p="${rest#*:}"
      [ "$p" = "$rest" ] && p="$VCS_HW_SERVER_PORT"
      [ -n "$h" ] || die "VCS_JTAG_MODE 'remote:' needs a host: remote:<host>[:<port>]"
      printf 'remote\t%s\t%s' "$h" "$p" ;;
    *)
      die "VCS_JTAG_MODE must be host, usb, remote:<host>[:<port>] or none (got: $VCS_JTAG_MODE)" ;;
  esac
}

# jtag_usb_devices -- print the /dev/bus/usb/<bus>/<dev> nodes of attached cables.
jtag_usb_devices() {
  have lsusb || return 0
  local vid_re
  vid_re="$(IFS='|'; printf '%s' "${VCS_JTAG_VIDS[*]}")"
  lsusb 2>/dev/null | awk -v re="^($vid_re):" '
    { id = $6 }
    id ~ re {
      bus = $2; dev = $4; sub(/:$/, "", dev)
      printf "/dev/bus/usb/%s/%s\n", bus, dev
    }' | sort -u
}

jtag_usb_describe() {
  have lsusb || { printf 'lsusb not installed; cannot enumerate cables'; return 0; }
  local vid_re
  vid_re="$(IFS='|'; printf '%s' "${VCS_JTAG_VIDS[*]}")"
  lsusb 2>/dev/null | awk -v re="^($vid_re):" '$6 ~ re { $1=$1; print }'
}

# jtag_args -- engine run arguments (one per line) plus the VCS_HW_SERVER_URL
# the in-container tools should connect to.
jtag_args() {
  local kind host port
  IFS=$'\t' read -r kind host port <<<"$(jtag_parse_mode)"

  case "$kind" in
    none)
      printf -- '--env\nVCS_HW_SERVER_URL=\n'
      return 0 ;;
    remote)
      engine_host_gateway_args
      printf -- '--env\nVCS_HW_SERVER_URL=TCP:%s:%s\n' "$host" "$port"
      return 0 ;;
    usb) ;;
  esac

  # --- usb passthrough ------------------------------------------------------
  [ -d /dev/bus/usb ] || die "--jtag usb requires /dev/bus/usb (Linux host with USB support)"
  local nodes=() n
  while IFS= read -r n; do [ -n "$n" ] && nodes+=("$n"); done < <(jtag_usb_devices)

  if [ "${VCS_JTAG_USB_ALL:-0}" -eq 1 ]; then
    # Survives replug (bus/device numbers change) at the cost of exposing every
    # USB device to the container.  Opt-in only.
    log_warn "passing the whole /dev/bus/usb tree into the container (VCS_JTAG_USB_ALL=1)"
    printf -- '--volume\n/dev/bus/usb:/dev/bus/usb%s\n' "$(engine_volume_suffix)"
    printf -- '--device-cgroup-rule\nc 189:* rwm\n'
  elif [ ${#nodes[@]} -eq 0 ]; then
    die "no JTAG cable found on the USB bus.
  Attached devices with a known vendor ID: (none)
  Fixes: plug the cable in, or run 'vcs jtag-rules --print' and install the udev
  rules so your user can open the device, or use the safer '--jtag host' mode."
  else
    for n in "${nodes[@]}"; do
      [ -r "$n" ] || log_warn "$n is not readable by $(id -un); see 'vcs jtag-rules --print'"
      printf -- '--device\n%s:%s:rwm\n' "$n" "$n"
    done
    log_debug "jtag: passing ${#nodes[@]} usb device node(s)"
  fi
  printf -- '--env\nVCS_HW_SERVER_URL=TCP:localhost:%s\n' "$port"
  printf -- '--env\nVCS_START_HW_SERVER=1\n'
}

jtag_describe() {
  local kind host port
  IFS=$'\t' read -r kind host port <<<"$(jtag_parse_mode)"
  case "$kind" in
    none)   printf 'disabled' ;;
    remote) printf 'TCP:%s:%s (hw_server runs outside the container)' "$host" "$port" ;;
    usb)    printf 'USB passthrough, hw_server runs inside the container' ;;
  esac
}

# jtag_udev_rules -- the rules that let a non-root user open a cable.  Printed,
# never written without the caller asking.
jtag_udev_rules() {
  cat <<'RULES'
# /etc/udev/rules.d/52-vivado-container-suite.rules
#
# Grant the physically-logged-in user (uaccess) and members of `plugdev`
# read/write access to Xilinx/Digilent/FTDI JTAG cables, so neither the host
# tools nor the container need to run as root.

# Xilinx Platform Cable USB / USB II
SUBSYSTEM=="usb", ATTR{idVendor}=="03fd", MODE="0660", GROUP="plugdev", TAG+="uaccess"

# Digilent (legacy VID)
SUBSYSTEM=="usb", ATTR{idVendor}=="1443", MODE="0660", GROUP="plugdev", TAG+="uaccess"

# FTDI-based cables: Digilent HS1/HS2/HS3, JTAG-SMT2/SMT3, Arty/Nexys on-board
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6010", MODE="0660", GROUP="plugdev", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6011", MODE="0660", GROUP="plugdev", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6014", MODE="0660", GROUP="plugdev", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6001", MODE="0660", GROUP="plugdev", TAG+="uaccess"
RULES
}
