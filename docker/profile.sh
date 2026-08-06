# shellcheck shell=sh
#
# Installed as /etc/profile.d/10-vivado.sh.  `vvd shell` starts bash as a login
# shell, which does not inherit the entrypoint's sourced Vivado settings.

_vvd_settings="${VVD_CONTAINER_XILINX_ROOT:-/opt/Xilinx}/${VVD_VIVADO_EDITION:-Vivado}/${VVD_VIVADO_VERSION:-2025.2}/settings64.sh"
if [ -f "$_vvd_settings" ] && ! command -v vivado >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$_vvd_settings"
fi
unset _vvd_settings

PS1='\[\033[1;35m\]vvd\[\033[0m\]:\w\$ '
export PS1
