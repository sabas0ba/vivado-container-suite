# shellcheck shell=bash
# vcs jtag-rules -- the host-side udev rules for JTAG cables.

VCS_UDEV_PATH=/etc/udev/rules.d/52-vivado-container-suite.rules

cmd_jtag_rules() {
  local action="print"
  while [ $# -gt 0 ]; do
    case "$1" in
      --print)   action="print"; shift ;;
      --install) action="install"; shift ;;
      --list)    action="list"; shift ;;
      -h|--help)
        cat <<H
vcs jtag-rules [--print|--install|--list]

  --print    Write the rules to stdout (default).  Review, then install with:
                vcs jtag-rules --print | sudo tee $VCS_UDEV_PATH
                sudo udevadm control --reload && sudo udevadm trigger
  --install  Do the above for you.  Requires root or a working sudo.
  --list     Show the JTAG cables currently attached to this host.

  These rules run on the HOST, not in the container: they are what lets your
  own user open the cable, so neither Vivado nor the container needs root.
H
        return 0 ;;
      *) die_usage "vcs jtag-rules: unexpected argument: $1" ;;
    esac
  done

  case "$action" in
    print) jtag_udev_rules ;;
    list)
      local out; out="$(jtag_usb_describe)"
      if [ -n "$out" ]; then printf '%s\n' "$out"
      else log_info "no JTAG cable with a known vendor ID is attached"; fi ;;
    install)
      local sudo_cmd=()
      if [ "$(id -u)" -ne 0 ]; then
        have sudo || die "not root and sudo is not installed; use --print and install the rules yourself"
        sudo_cmd=(sudo)
      fi
      log_info "installing $VCS_UDEV_PATH"
      jtag_udev_rules | "${sudo_cmd[@]}" tee "$VCS_UDEV_PATH" >/dev/null
      "${sudo_cmd[@]}" udevadm control --reload
      "${sudo_cmd[@]}" udevadm trigger --subsystem-match=usb
      log_ok "installed; replug the cable for the new permissions to take effect"
      if ! id -nG | tr ' ' '\n' | grep -qx plugdev; then
        log_warn "you are not in the 'plugdev' group; either add yourself (sudo usermod -aG plugdev $(id -un)) or rely on the uaccess tag for locally logged-in sessions"
      fi ;;
  esac
}
