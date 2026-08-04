# syntax=docker/dockerfile:1.7
#
# vivado-container-suite image.
#
#   target `base`    -- everything Vivado needs, but not Vivado itself.  Vivado
#                       is bind-mounted from the host at run time.  ~1.5 GB.
#   target `vivado`  -- base + Vivado installed from a host-supplied installer.
#                       Self-contained but 100 GB+.  See docs/03-image-build.md.
#
# Pinning:
#   * BASE_IMAGE is always a digest (config/images.lock).
#   * The apt archive is pinned to an immutable snapshot, which freezes the
#     whole transitive dependency closure; top-level versions are additionally
#     pinned from docker/packages.lock.
#   * The Vivado installer's SHA256 is checked by `vcs build` before the build
#     starts and again inside the image.

ARG BASE_IMAGE=ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea

# =============================================================================
# Bootstrap: obtain a CA bundle.
#
# snapshot.ubuntu.com is HTTPS-only and ubuntu:24.04 ships no root certificates,
# so the pinned install cannot make its first TLS connection without one.  This
# stage exists purely to produce that bundle; nothing it builds reaches the
# final image except the certificate file, and that file is deleted in the same
# layer that uses it.  Package integrity never depends on it: apt verifies the
# GPG-signed InRelease -> Packages -> SHA256 chain for every .deb regardless of
# how the bytes arrived.
# EXTRA_CA_CERT names a file inside the `cacerts` build context.  Set it when
# the build sits behind a TLS-inspecting proxy, whose certificate would
# otherwise make snapshot.ubuntu.com unreachable: `vcs build --ca-cert FILE`.
# It is trusted only while the image is being built -- the runtime trust store
# comes from the pinned ca-certificates package and never includes it.
FROM ${BASE_IMAGE} AS ca-bootstrap
ARG DEBIAN_FRONTEND=noninteractive
ARG EXTRA_CA_CERT=
# hadolint ignore=DL3008,DL3009
RUN --mount=type=bind,from=cacerts,target=/mnt/cacerts,readonly \
    set -eu; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates; \
    if [ -n "$EXTRA_CA_CERT" ]; then \
      cp "/mnt/cacerts/$EXTRA_CA_CERT" /usr/local/share/ca-certificates/vcs-build-proxy.crt; \
      update-ca-certificates; \
    fi

# =============================================================================
FROM ${BASE_IMAGE} AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG VIVADO_VERSION=2025.2
ARG VIVADO_EDITION=Vivado
ARG DEBIAN_FRONTEND=noninteractive

COPY docker/apt-snapshot.lock docker/packages.lock /opt/vcs/pin/
# Deliberately not /etc/ssl/certs: the standard locations must be populated only
# by the pinned ca-certificates package, never by this transient copy.
COPY --from=ca-bootstrap /etc/ssl/certs/ca-certificates.crt /opt/vcs/pin/ca-bootstrap.crt

# Point apt at the pinned snapshot, then install exactly the locked versions.
# hadolint ignore=DL3008,DL3009
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -euo pipefail; \
    . /opt/vcs/pin/apt-snapshot.lock; \
    : "${APT_SNAPSHOT:?apt-snapshot.lock did not define APT_SNAPSHOT}"; \
    printf 'Types: deb\nURIs: https://snapshot.ubuntu.com/ubuntu/%s\nSuites: %s\nComponents: %s\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' \
        "$APT_SNAPSHOT" "$APT_POCKETS" "$APT_COMPONENTS" \
        > /etc/apt/sources.list.d/ubuntu.sources; \
    rm -f /etc/apt/sources.list; \
    printf 'Acquire::Check-Valid-Until "false";\nAcquire::Retries "5";\nAcquire::https::CaInfo "/opt/vcs/pin/ca-bootstrap.crt";\n' \
        > /etc/apt/apt.conf.d/99vcs; \
    mapfile -t pkgs < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' /opt/vcs/pin/packages.lock); \
    [ "${#pkgs[@]}" -gt 0 ] || { echo "packages.lock is empty" >&2; exit 1; }; \
    apt-get update; \
    apt-get install -y --no-install-recommends "${pkgs[@]}"; \
    test -s /etc/ssl/certs/ca-certificates.crt; \
    rm -f /opt/vcs/pin/ca-bootstrap.crt; \
    printf 'Acquire::Check-Valid-Until "false";\nAcquire::Retries "5";\n' \
        > /etc/apt/apt.conf.d/99vcs; \
    rm -rf /var/lib/apt/lists/*

# Vivado's Tcl and a handful of IP flows still look for the SONAME-5 curses
# libraries that Ubuntu dropped after 20.04.  The ABI is compatible for the
# symbols they use, so a link is the supported workaround.
RUN set -euo pipefail; \
    for pair in "libtinfo.so.6 libtinfo.so.5" "libncurses.so.6 libncurses.so.5" "libncursesw.so.6 libncursesw.so.5"; do \
      read -r src dst <<<"$pair"; \
      if [ -e "/lib/x86_64-linux-gnu/$src" ] && [ ! -e "/lib/x86_64-linux-gnu/$dst" ]; then \
        ln -s "$src" "/lib/x86_64-linux-gnu/$dst"; \
      fi; \
    done; \
    ldconfig

RUN set -euo pipefail; \
    locale-gen en_US.UTF-8; \
    groupadd --gid 1500 vivado; \
    useradd --uid 1500 --gid 1500 --create-home --home-dir /home/vivado --shell /bin/bash vivado; \
    groupadd --system --gid 1501 plugdev 2>/dev/null || true; \
    usermod -aG plugdev vivado; \
    mkdir -p /work /opt/Xilinx /opt/vcs/license /opt/vcs/tcl /opt/vcs/lib; \
    chown vivado:vivado /work /home/vivado

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    HOME=/home/vivado \
    VIVADO_VERSION=${VIVADO_VERSION} \
    VIVADO_EDITION=${VIVADO_EDITION} \
    VCS_CONTAINER_XILINX_ROOT=/opt/Xilinx \
    VCS_CONTAINER_TCL=/opt/vcs/tcl \
    XILINX_LOCAL_USER_DATA=no \
    RDI_VERBOSE=0

COPY docker/entrypoint.sh /usr/local/bin/vcs-entrypoint
COPY docker/profile.sh /etc/profile.d/10-vivado.sh
RUN chmod 0755 /usr/local/bin/vcs-entrypoint

# A license must never be baked in; fail the build loudly if one sneaks into
# the context.
RUN set -euo pipefail; \
    if find / -xdev -name '*.lic' -not -path '/proc/*' | grep -q .; then \
      echo "refusing to ship an image containing a .lic file" >&2; exit 1; \
    fi

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/vcs-entrypoint"]
CMD ["bash", "-l"]

LABEL org.opencontainers.image.title="vivado-container-suite" \
      org.opencontainers.image.description="Containerised AMD Vivado, CLI first" \
      org.opencontainers.image.source="https://github.com/sabas0ba/vivado-container-suite" \
      org.opencontainers.image.licenses="MIT" \
      io.vcs.vivado.version="${VIVADO_VERSION}" \
      io.vcs.vivado.mode="mount"

# =============================================================================
FROM base AS vivado

ARG VIVADO_VERSION=2025.2
ARG VIVADO_EDITION=Vivado
ARG VIVADO_INSTALLER
ARG VIVADO_EDITION_NAME="Vivado ML Standard"

COPY docker/install-vivado.sh /opt/vcs/install-vivado.sh
COPY config/vivado-versions.lock /opt/vcs/pin/vivado-versions.lock

# The installer tarball is provided as a named build context so it is streamed
# rather than copied into the layer cache -- these files are 30-100 GB.
RUN --mount=type=bind,from=installer,target=/mnt/installer,readonly \
    set -euo pipefail; \
    : "${VIVADO_INSTALLER:?build with: vcs build --installer <tarball>}"; \
    /opt/vcs/install-vivado.sh "/mnt/installer/${VIVADO_INSTALLER}"

ENV VCS_VIVADO_MODE=image
LABEL io.vcs.vivado.mode="image"
