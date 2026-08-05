#!/usr/bin/env bash
# Refuse to ship an image containing license material.
#
# Runs as the last step of the base stage, so it sees everything any earlier
# COPY or RUN put in the image, whatever route it arrived by.
set -euo pipefail

found="$(find / -xdev -name '*.lic' -not -path '/proc/*' -print -quit)"
if [ -n "$found" ]; then
  echo "refusing to ship an image containing a .lic file: $found" >&2
  exit 1
fi
echo "check-no-license: clean" >&2
