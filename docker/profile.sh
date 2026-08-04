# shellcheck shell=sh
#
# Installed as /etc/profile.d/10-vivado.sh.  `vcs shell` starts bash as a login
# shell, which does not inherit the entrypoint's sourced Vivado settings.

_vcs_settings="${VCS_CONTAINER_XILINX_ROOT:-/opt/Xilinx}/${VCS_VIVADO_EDITION:-Vivado}/${VCS_VIVADO_VERSION:-2025.2}/settings64.sh"
if [ -f "$_vcs_settings" ] && ! command -v vivado >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$_vcs_settings"
fi
unset _vcs_settings

PS1='\[\033[1;35m\]vcs\[\033[0m\]:\w\$ '
export PS1
