# shellcheck shell=bash
# vcs image -- print the image reference in use.

cmd_image() {
  printf '%s\n' "$VCS_IMAGE"
}
