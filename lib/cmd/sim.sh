# shellcheck shell=bash
# vvd sim -- behavioural simulation with the built-in xsim compiler.

cmd_sim() {
  local gui=0 waves=1 sim_top="" runtime=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --gui)      gui=1; shift ;;
      --vnc)      gui=1; VVD_VNC=1; VVD_DISPLAY_MODE=xvfb
                  export VVD_VNC VVD_DISPLAY_MODE; shift ;;
      --no-waves) waves=0; shift ;;
      --top)      sim_top="${2:?--top needs a module}"; shift 2 ;;
      --time)     runtime="${2:?--time needs a value, e.g. 200ns}"; shift 2 ;;
      -h|--help)
        cat <<'H'
vvd sim [options]

  --gui         Open the xsim waveform viewer instead of running headless
  --vnc         As --gui, but export the viewer over VNC (see `vvd gui --help`)
  --top MOD     Testbench top module (default: VVD_SIM_TOP)
  --time T      Simulation length, e.g. 500ns (default: VVD_SIM_TIME, else run -all)
  --no-waves    Do not record a waveform database

Sources come from VVD_SIM_SOURCES / VVD_SIM_VHDL_SOURCES plus the design
sources; the waveform database lands in <build>/sim/<top>.wdb.
H
        return 0 ;;
      *) die_usage "vvd sim: unexpected argument: $1" ;;
    esac
  done

  [ -n "$sim_top" ] && VVD_SIM_TOP="$sim_top"
  [ -n "$runtime" ] && VVD_SIM_TIME="$runtime"
  export VVD_SIM_TOP VVD_SIM_TIME
  require_project_settings VVD_SIM_TOP

  VVD_SIM_WAVES="$waves"
  export VVD_SIM_WAVES

  if [ "$gui" -eq 1 ]; then
    local mode; mode="$(display_effective_mode)"
    [ "$mode" = "none" ] &&
      die "vvd sim --gui needs a display; use --display x11 (X forwarding) or --display xvfb"
    log_info "sim (gui): $VVD_SIM_TOP"
    exec_in_container 1 /opt/vvd/lib/sim.sh --gui
  else
    log_info "sim: $VVD_SIM_TOP"
    run_in_container 0 /opt/vvd/lib/sim.sh
  fi
}
