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
#
# Portability: every RUN here is a single command with no shell syntax of its
# own.  The `SHELL` instruction is silently ignored when an image is built in
# OCI format (podman/buildah default, including behind a `docker` shim), which
# drops RUN back to /bin/sh -- so the real work lives in scripts with explicit
# bash shebangs instead of inline in a RUN.

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

ARG VIVADO_VERSION=2025.2
ARG VIVADO_EDITION=Vivado
ARG DEBIAN_FRONTEND=noninteractive

COPY docker/apt-snapshot.lock docker/packages.lock docker/install-packages.sh /opt/vcs/pin/
# Deliberately not /etc/ssl/certs: the standard locations must be populated only
# by the pinned ca-certificates package, never by this transient copy.
COPY --from=ca-bootstrap /etc/ssl/certs/ca-certificates.crt /opt/vcs/pin/ca-bootstrap.crt

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    /opt/vcs/pin/install-packages.sh

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    HOME=/home/vivado \
    VIVADO_VERSION=${VIVADO_VERSION} \
    VIVADO_EDITION=${VIVADO_EDITION} \
    VCS_CONTAINER_XILINX_ROOT=/opt/Xilinx \
    VCS_CONTAINER_TCL=/opt/vcs/tcl \
    XILINX_LOCAL_USER_DATA=no \
    RDI_VERBOSE=0

COPY docker/setup-image.sh /opt/vcs/pin/setup-image.sh
RUN /opt/vcs/pin/setup-image.sh

COPY docker/entrypoint.sh /usr/local/bin/vcs-entrypoint
COPY docker/profile.sh /etc/profile.d/10-vivado.sh
RUN chmod 0755 /usr/local/bin/vcs-entrypoint

# Last step of the stage, so it sees everything every earlier layer added.
COPY docker/check-no-license.sh /opt/vcs/pin/check-no-license.sh
RUN /opt/vcs/pin/check-no-license.sh

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
    /opt/vcs/install-vivado.sh "/mnt/installer/${VIVADO_INSTALLER}"

ENV VCS_VIVADO_MODE=image
LABEL io.vcs.vivado.mode="image"
