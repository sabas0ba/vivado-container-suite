# shellcheck shell=bash
# vcs doctor -- is this host able to run the suite, and is the image sound?

VCS_DOCTOR_FAIL=0
VCS_DOCTOR_WARN=0

_chk_ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
_chk_warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; VCS_DOCTOR_WARN=$((VCS_DOCTOR_WARN+1)); }
_chk_fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; VCS_DOCTOR_FAIL=$((VCS_DOCTOR_FAIL+1)); }
_chk_note() { printf '        %s\n' "$*"; }

cmd_doctor() {
  local deep=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --deep) deep=1; shift ;;
      -h|--help) echo "vcs doctor [--deep]   check host, engine, image, license and JTAG (--deep also starts the container)"; return 0 ;;
      *) die_usage "vcs doctor: unexpected argument: $1" ;;
    esac
  done

  if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
    _chk_ok()   { printf '  ok    %s\n' "$*"; }
    _chk_warn() { printf '  warn  %s\n' "$*"; VCS_DOCTOR_WARN=$((VCS_DOCTOR_WARN+1)); }
    _chk_fail() { printf '  FAIL  %s\n' "$*"; VCS_DOCTOR_FAIL=$((VCS_DOCTOR_FAIL+1)); }
  fi

  echo "host"
  case "$(uname -s)" in
    Linux) _chk_ok "Linux $(uname -r)" ;;
    *)     _chk_warn "$(uname -s) -- USB JTAG passthrough and X11 forwarding are Linux-only; use --jtag remote:" ;;
  esac
  case "$(uname -m)" in
    x86_64) _chk_ok "x86_64" ;;
    *)      _chk_fail "$(uname -m): Vivado is x86_64 only; emulation is not supported" ;;
  esac
  local avail
  avail="$(df -Pk "$VCS_PROJECT_ROOT" 2>/dev/null | awk 'NR==2 {print int($4/1048576)}')" || avail=""
  if [ -n "$avail" ]; then
    if [ "$avail" -lt 20 ]; then _chk_warn "only ${avail}GiB free under $VCS_PROJECT_ROOT; implementation runs need room"
    else _chk_ok "${avail}GiB free under $VCS_PROJECT_ROOT"; fi
  fi

  echo "engine"
  if engine_detect 2>/dev/null && [ -n "$VCS_ENGINE_BIN" ]; then
    _chk_ok "$VCS_ENGINE_BIN found$( [ "$VCS_ENGINE_ROOTLESS" -eq 1 ] && printf ' (rootless)')"
    if engine_available; then
      _chk_ok "$VCS_ENGINE_BIN is usable"
    else
      _chk_fail "$VCS_ENGINE_BIN cannot talk to its backend"
      _chk_note "docker: is the daemon running, and are you in the 'docker' group?"
      _chk_note "podman: try 'podman system migrate' or check /etc/subuid"
    fi
  else
    _chk_fail "neither podman nor docker found on PATH"
  fi

  echo "image"
  if [ -n "$VCS_ENGINE_BIN" ] && image_exists "$VCS_IMAGE"; then
    _chk_ok "$VCS_IMAGE present"
  else
    _chk_warn "$VCS_IMAGE not present -- run 'vcs build'"
  fi

  echo "vivado"
  case "$VCS_VIVADO_MODE" in
    mount)
      local settings="$VCS_XILINX_ROOT/$VCS_VIVADO_EDITION/$VCS_VIVADO_VERSION/settings64.sh"
      if [ -f "$settings" ]; then
        _chk_ok "Vivado $VCS_VIVADO_VERSION at $VCS_XILINX_ROOT (bind-mounted read-only)"
      else
        _chk_fail "Vivado $VCS_VIVADO_VERSION not found: $settings"
        _chk_note "versions present:$(vivado_versions_present "$VCS_XILINX_ROOT")"
        _chk_note "or switch to VCS_VIVADO_MODE=image (see docs/03-image-build.md)"
      fi ;;
    image)
      _chk_ok "Vivado is expected inside $VCS_IMAGE" ;;
    none)
      _chk_warn "VCS_VIVADO_MODE=none: no Vivado. Flows will fail; container-level checks still run" ;;
  esac

  echo "license"
  local spec kind
  spec="$(license_resolve)"; kind="$(license_kind "$spec")"
  case "$kind" in
    none)   _chk_warn "no license configured; synthesis of licensed devices will fail"
            _chk_note "set VCS_LICENSE=port@host, or VCS_LICENSE=/path/to/Xilinx.lic" ;;
    server) _chk_ok "floating license server: $spec"
            local h p
            p="${spec%%@*}"; h="${spec#*@}"
            if [[ "$p" =~ ^[0-9]+$ ]] && have bash; then
              if timeout 3 bash -c "exec 3<>/dev/tcp/$h/$p" 2>/dev/null; then _chk_ok "reachable: $h:$p"
              else _chk_warn "cannot reach $h:$p from this host (VPN down? firewall?)"; fi
            fi ;;
    file)   if [ -r "$spec" ]; then _chk_ok "node-locked license readable: $spec"
            else _chk_fail "license file not readable: $spec"; fi ;;
    dir)    local d="${spec#dir:}"
            if [ -d "$d" ]; then _chk_ok "license directory: $d"
            else _chk_fail "license directory missing: $d"; fi ;;
    *)      _chk_fail "unrecognised VCS_LICENSE: $spec" ;;
  esac

  echo "display"
  local dmode; dmode="$(display_effective_mode 2>/dev/null || echo none)"
  case "$dmode" in
    x11)  _chk_ok "X11 forwarding via $DISPLAY"
          have xauth || _chk_warn "xauth is not installed; no per-run cookie will be created" ;;
    xvfb) _chk_ok "headless Xvfb (GUI available but not displayed)" ;;
    none) _chk_warn "no display; 'vcs gui' will refuse to start (batch flows are unaffected)" ;;
  esac

  echo "jtag"
  local jkind jhost jport
  IFS=$'\t' read -r jkind jhost jport <<<"$(jtag_parse_mode 2>/dev/null || printf 'none\t\t')"
  case "$jkind" in
    none) _chk_warn "JTAG disabled (VCS_JTAG_MODE=none)" ;;
    remote)
      _chk_ok "remote hw_server: $jhost:$jport"
      if [ "$VCS_JTAG_MODE" = "host" ]; then
        if timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$jport" 2>/dev/null; then
          _chk_ok "hw_server is listening on the host (127.0.0.1:$jport)"
        else
          _chk_warn "nothing is listening on 127.0.0.1:$jport"
          _chk_note "start it on the host:  hw_server"
          _chk_note "or run it in a container:  vcs hw-server"
        fi
      fi ;;
    usb)
      local cables; cables="$(jtag_usb_describe)"
      if [ -n "$cables" ]; then
        _chk_ok "cable(s) attached:"
        printf '        %s\n' "$cables"
        local n unreadable=0
        while IFS= read -r n; do [ -n "$n" ] && { [ -r "$n" ] || unreadable=1; }; done < <(jtag_usb_devices)
        if [ "$unreadable" -eq 1 ]; then
          _chk_fail "the device node is not readable by $(id -un)"
          _chk_note "install the udev rules:  vcs jtag-rules --install"
        else
          _chk_ok "device node permissions look right"
        fi
      else
        _chk_warn "no cable with a known vendor ID attached"
      fi ;;
  esac

  echo "pinning"
  if "$VCS_ROOT/scripts/verify-pinning.sh" --quiet; then
    _chk_ok "all images, packages and actions are digest/SHA pinned"
  else
    _chk_fail "unpinned dependency found -- run scripts/verify-pinning.sh"
  fi

  if [ "$deep" -eq 1 ]; then
    echo "container"
    if [ "$VCS_DOCTOR_FAIL" -gt 0 ]; then
      _chk_warn "skipping the in-container checks because earlier checks failed"
    elif run_in_container 0 /opt/vcs/lib/doctor.sh; then
      _chk_ok "in-container checks passed"
    else
      _chk_fail "in-container checks failed"
    fi
  fi

  printf '\n'
  if [ "$VCS_DOCTOR_FAIL" -gt 0 ]; then
    log_error "$VCS_DOCTOR_FAIL failure(s), $VCS_DOCTOR_WARN warning(s)"
    return 1
  fi
  log_ok "no failures, $VCS_DOCTOR_WARN warning(s)"
}
