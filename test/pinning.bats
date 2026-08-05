#!/usr/bin/env bats
# Supply-chain pinning is a hard requirement, so it gets its own tests.

load helper
setup()    { load_helpers; setup_project; }
teardown() { teardown_project; }

@test "verify-pinning passes on a clean tree" {
  run "$VCS_REPO_ROOT/scripts/verify-pinning.sh"
  [ "$status" -eq 0 ]
}

@test "verify-pinning catches an unpinned base image" {
  work="$TMP/repo"
  cp -r "$VCS_REPO_ROOT" "$work"
  rm -rf "$work/.git"
  sed -i 's|^ARG BASE_IMAGE=.*|ARG BASE_IMAGE=ubuntu:24.04|' "$work/docker/Dockerfile"
  run "$work/scripts/verify-pinning.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not digest-pinned"* ]]
}

@test "verify-pinning catches an unpinned GitHub action" {
  work="$TMP/repo2"
  cp -r "$VCS_REPO_ROOT" "$work"
  rm -rf "$work/.git"
  mkdir -p "$work/.github/workflows"
  printf 'jobs:\n  a:\n    steps:\n      - uses: actions/checkout@v4\n' \
    >"$work/.github/workflows/bad.yml"
  run "$work/scripts/verify-pinning.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not pinned to a commit SHA"* ]]
}

@test "verify-pinning catches a package added to the list but not locked" {
  work="$TMP/repo3"
  cp -r "$VCS_REPO_ROOT" "$work"
  rm -rf "$work/.git"
  echo 'cowsay' >>"$work/docker/packages.list"
  run "$work/scripts/verify-pinning.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cowsay"* ]]
}

@test "every locked package carries a version and a sha256" {
  while read -r line; do
    [[ "$line" == \#* ]] && continue
    [ -z "$line" ] && continue
    [[ "$line" == *"="* ]] || { echo "no version: $line"; false; }
    [[ "$line" == *"# sha256:"* ]] || { echo "no sha256: $line"; false; }
  done <"$VCS_REPO_ROOT/docker/packages.lock"
}

@test "the apt snapshot is an immutable timestamp" {
  run grep -E '^APT_SNAPSHOT=[0-9]{8}T[0-9]{6}Z$' "$VCS_REPO_ROOT/docker/apt-snapshot.lock"
  [ "$status" -eq 0 ]
}

@test "images.lock entries are all digests" {
  while IFS='|' read -r key ref; do
    [[ "$key" == \#* ]] && continue
    [ -z "$key" ] && continue
    [[ "$ref" == *"@sha256:"* ]] || { echo "$key is not digest-pinned"; false; }
  done <"$VCS_REPO_ROOT/config/images.lock"
}

@test "the tool lock pins by sha256 or commit id" {
  while IFS='|' read -r kind name a b _; do
    case "$kind" in ''|\#*) continue ;; esac
    case "$kind" in
      bin|tar) [[ "$b" =~ ^[0-9a-f]{64}$ ]] || { echo "$name: bad sha256"; false; } ;;
      git)     [[ "$b" =~ ^[0-9a-f]{40}$ ]] || { echo "$name: bad commit"; false; } ;;
    esac
    : "$a"
  done <"$VCS_REPO_ROOT/scripts/tools.lock"
}

@test "no script fetches and executes in one step" {
  run grep -rnE '(curl|wget)[^|]*\|[[:space:]]*(ba)?sh' \
      "$VCS_REPO_ROOT/bin" "$VCS_REPO_ROOT/lib" "$VCS_REPO_ROOT/scripts" \
      "$VCS_REPO_ROOT/docker" "$VCS_REPO_ROOT/container"
  [ "$status" -ne 0 ]
}

@test "the Vivado installer digest is enforced by both the CLI and the image" {
  grep -q 'sha256sum' "$VCS_REPO_ROOT/lib/cmd/build.sh"
  grep -q 'sha256sum' "$VCS_REPO_ROOT/docker/install-vivado.sh"
}

@test "verify-pinning catches a new unpinned apt-get install" {
  work="$TMP/repo4"
  cp -r "$VCS_REPO_ROOT" "$work"
  rm -rf "$work/.git" "$work/.tools"
  printf '\nRUN apt-get install -y cowsay\n' >>"$work/docker/Dockerfile"
  run "$work/scripts/verify-pinning.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the packages.lock path"* ]]
}

@test "verify-pinning catches a bootstrap CA bundle left in the image" {
  work="$TMP/repo5"
  cp -r "$VCS_REPO_ROOT" "$work"
  rm -rf "$work/.git" "$work/.tools"
  sed -i 's|rm -f "$BOOTSTRAP_CA"|true|' "$work/docker/install-packages.sh"
  run "$work/scripts/verify-pinning.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bootstrap CA bundle"* ]]
}

@test "the build-time CA is never added to the runtime trust store" {
  # It lands under /opt/vcs/pin, never /etc/ssl/certs or the update-ca-certificates
  # source directory of the final stage.
  run grep -n 'ca-bootstrap' "$VCS_REPO_ROOT/docker/Dockerfile"
  [ "$status" -eq 0 ]
  refute_output_contains "$output" "/etc/ssl/certs/ca-bootstrap"
}

@test "no RUN instruction depends on bash: SHELL is ignored under OCI format" {
  # A `docker` that is really podman/buildah builds in OCI format, where the
  # SHELL instruction is silently dropped and RUN falls back to /bin/sh.  Any
  # bashism in a RUN body is a syntax error there, so the real work belongs in
  # a script with its own shebang.
  run grep -nE "^\s+(set -[a-z]* *-?o pipefail|mapfile|readarray)|<<<|\[\[" \
      "$VCS_REPO_ROOT/docker/Dockerfile"
  [ "$status" -ne 0 ] || { echo "bashism in a Dockerfile RUN:"; echo "$output"; false; }
}

@test "the Dockerfile does not rely on the SHELL instruction" {
  run grep -n '^SHELL' "$VCS_REPO_ROOT/docker/Dockerfile"
  [ "$status" -ne 0 ]
}

@test "every script the image runs has an explicit interpreter" {
  for f in "$VCS_REPO_ROOT"/docker/*.sh "$VCS_REPO_ROOT"/container/*.sh; do
    # profile.sh is sourced by the login shell, not executed.
    [ "$(basename "$f")" = "profile.sh" ] && continue
    head -n1 "$f" | grep -q '^#!' || { echo "no shebang: $f"; false; }
    [ -x "$f" ] || { echo "not executable: $f"; false; }
  done
}
