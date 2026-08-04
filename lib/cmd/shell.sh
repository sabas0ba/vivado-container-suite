# shellcheck shell=bash
# vcs shell -- a shell inside the container, with the Vivado environment sourced.

cmd_shell() {
  case "${1:-}" in
    -h|--help)
      cat <<'H'
vcs shell [COMMAND [ARGS...]]

  With no COMMAND: an interactive bash with Vivado, vitis-2-tcl (xsct), xsim and
  hw_server on PATH, the project mounted at /work and $HOME persisted in the
  suite's cache directory.

  With a COMMAND: runs it non-interactively -- handy in scripts and CI, e.g.
      vcs shell vivado -version
      vcs shell xsim --version
H
      return 0 ;;
  esac

  if [ $# -eq 0 ]; then
    exec_in_container 1 bash -l
  else
    run_in_container 0 "$@"
  fi
}
