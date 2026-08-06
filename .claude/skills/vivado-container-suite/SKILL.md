---
name: vivado-container-suite
description: Drive AMD Vivado inside a container entirely from the CLI via the `vvd` tool - synthesis, implementation, bitstream, xsim simulation, JTAG programming, the Tcl console and the GUI. Use when the task involves an FPGA/Vivado flow, a vvd.conf project, container-wrapped EDA tooling, Xilinx licensing, hw_server/JTAG, or when a repository contains bin/vvd or vvd.conf.
---

# vivado-container-suite (`vvd`)

Containerised Vivado, CLI-first. Vivado itself is bind-mounted from the host by
default; the image only carries its runtime dependencies.

## Orientation

Run these before anything else when entering an unfamiliar project:

```sh
vvd info            # resolved configuration: part, top, flow mode, image, paths
vvd doctor          # host, engine, image, Vivado, license, display, JTAG, pinning
vvd --dry-run <cmd> # the exact container command, without running it
```

`vvd` walks up from the current directory to find `vvd.conf`, so it works from
any subdirectory. `-C <dir>` targets a different project.

## Commands

| Command | Purpose |
|---|---|
| `vvd build` | Build the image. `--installer TARBALL` bakes Vivado in; `--ca-cert FILE` for TLS-inspecting proxies |
| `vvd synth` / `impl` / `bitstream` | One flow stage each; later stages run earlier ones if needed |
| `vvd flow` | All three in a single Vivado invocation (faster) |
| `vvd sim [--gui] [--top M] [--time T]` | xsim simulation |
| `vvd program [--bit F] [--target PAT] [--list]` | JTAG download |
| `vvd hw-server [--port N] [--bind ADDR]` | hw_server in the container, port published |
| `vvd tcl [SCRIPT]` / `vvd run SCRIPT [ARGS]` | Tcl console / batch script |
| `vvd gui [XPR\|DCP]` | Vivado IDE |
| `vvd shell [CMD...]` | Shell with Vivado on PATH |
| `vvd doctor [--deep]` / `vvd selftest [--stage S]` | Diagnostics / availability tests |
| `vvd clean [-f] [--all]` | Remove build output |
| `vvd jtag-rules [--print\|--install\|--list]` | Host udev rules for JTAG cables |

Global flags: `-C/--project`, `--config`, `--vivado`, `--engine`, `--image`,
`--license`, `--display`, `--jtag`, `--part`, `--top`, `--build-dir`, `--gpu`,
`-n/--dry-run`, `-v/--verbose`, `-q/--quiet`.

## Configuration

`vvd.conf` at the project root. `KEY=VALUE` only — it is parsed, not sourced, so
`$(...)` does not work. Unknown keys are a hard error.

Precedence: built-in defaults < `vvd.conf` < `vvd.local.conf` (git-ignored,
machine-specific) < `VVD_*` environment < CLI flags.

Minimum viable project:

```conf
VVD_PART=xc7a35ticsg324-1L
VVD_TOP=blinky
VVD_SOURCES=rtl/*.v
VVD_CONSTRAINTS=constr/*.xdc
VVD_SIM_TOP=tb_blinky
VVD_SIM_SOURCES=sim/*.v
```

Every key is listed in `docs/02-configuration.md`; `vvd info --all` prints the
resolved values.

## Rules to respect when editing this repository

- **Never put a license anywhere near the image.** Licenses arrive at run time
  as `XILINXD_LICENSE_FILE` or a read-only bind mount. The Dockerfile fails the
  build if a `.lic` is present, and CI re-checks the built image.
- **`VVD_VIVADO_MODE`** is `mount` (bind the host install, default), `image`
  (baked in) or `none` (no Vivado — container-level checks only).
- **Never add an unpinned dependency.** Base images by digest, apt through the
  Ubuntu snapshot in `docker/apt-snapshot.lock` plus `docker/packages.lock`,
  tools by sha256 or commit id in `scripts/tools.lock`, GitHub Actions by commit
  SHA. `scripts/verify-pinning.sh` enforces all of it and runs in CI. To add an
  apt package: add the name to `docker/packages.list`, then run
  `scripts/lock-apt.sh`. The one sanctioned exception is the `ca-bootstrap`
  stage, which fetches a transient CA bundle because snapshot.ubuntu.com is
  HTTPS-only and the base image has no trust store; that bundle is deleted in
  the layer that uses it, and the check enforces both facts.
- **Never reach for `--privileged` or a blanket `/dev` mount** for JTAG. The
  default transport is a TCP connection to a `hw_server` outside the container;
  USB mode passes only the matching device nodes.
- **Validate on the host, before starting the container.** Missing files, bad
  versions, paths outside the project root — all of these should fail with an
  actionable message before an image is pulled or a container runs.
- **Argument emitters run in subshells.** Anything in `lib/run.sh` that prints
  engine arguments is collected through command substitution, so a `die` inside
  one only aborts because `_collect` checks the status. State mutation (temp
  files, cleanup registration) belongs in a `*_prepare` function that runs in
  the parent — see `display_prepare`.
- **A source glob that matches nothing is an error**, not an empty design. This
  holds in `tcl/lib.tcl` and `container/sim.sh` alike.
- **Timing violations fail the build** unless `VVD_ALLOW_TIMING_VIOLATION=1`.
  Vivado's own exit code does not reflect timing.

## Layout

```
bin/vvd               entry point: global flags, config resolution, dispatch
lib/*.sh              log, config, engine, license, display, usb (JTAG), run, flow
lib/cmd/<name>.sh     one file per subcommand, defining cmd_<name>
tcl/                  mounted read-only at /opt/vvd/tcl — edit without rebuilding
container/            mounted read-only at /opt/vvd/lib — sim, doctor, selftest
docker/               Dockerfile, entrypoint, apt and package locks
config/               defaults, image and Vivado installer locks
scripts/              lock generation, pinning verification, tool fetch
test/*.bats           unit tests driven by a fake engine in test/fixtures/bin
```

Adding a subcommand: create `lib/cmd/<name>.sh` defining `cmd_<name>` (dashes
become underscores), list it in `usage()` in `bin/vvd`, and add it to the two
loops in `test/cli.bats`.

## Verification

```sh
make check          # pinning + shellcheck + hadolint + Tcl syntax + bats
make test           # bats only
vvd selftest        # in-container availability tests
```

`vvd selftest` stages: `image libs identity display env version tcl license sim
synth jtag`. A stage whose precondition is absent skips (exit 77) instead of
failing. `VVD_VIVADO_MODE=none` declares that this container has no Vivado at
all — nothing is mounted, no host lookup happens, and the Vivado-dependent
stages skip. That is how CI exercises the container on a runner without an
installation.

## Diagnosing a failure

1. `vvd doctor` — nearly every environment problem is named here with its fix.
2. `vvd --dry-run <cmd>` — check the assembled container command.
3. `vvd selftest --stage <s>` — isolate which layer broke.
4. `vvd shell` — get inside and look.

`docs/10-troubleshooting.md` maps symptoms to causes.
