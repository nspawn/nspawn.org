---
title: Contributing
weight: 12
description: >-
  Where the code lives, how to build and test it, and how to send changes.
---

nspawn is developed on GitHub under the [nspawn organization](https://github.com/nspawn):

| Repository | What it holds |
| --- | --- |
| [nspawn](https://github.com/nspawn/nspawn) | The tool (Rust). |
| [mkosi-definitions](https://github.com/nspawn/mkosi-definitions) | The mkosi configuration of the images on the hub. |
| [nspawn.org](https://github.com/nspawn/nspawn.org) | This site. |
| [nspawn.github.io](https://github.com/nspawn/nspawn.github.io) | The [blog](https://blog.nspawn.org/). |

Issues and pull requests are welcome in all of them. The
[code of conduct](https://github.com/nspawn/coc) applies everywhere.

## Working on the tool

A Rust toolchain of version 1.85 or newer is enough for the unit tests and
clippy, which need no root and touch nothing outside temporary directories:

```shell
cargo fmt
cargo clippy --all-targets -- -D warnings
cargo test
cargo build --release
```

The repository documents itself: `docs/HACKING.md` for building and testing,
`docs/ARCHITECTURE.md` for how the pieces fit, `docs/DBUS.md` for the interface
the service exposes, and `packaging/` for the Fedora, Arch and Debian packages
and the SELinux policy. A pull request runs the checks and builds those
packages.

A binary you built has to be installed before it can serve:
`sudo install -Dm755 target/release/nspawn /usr/local/bin/nspawn` followed by
`sudo nspawn daemon --install`. Replacing the binary of a running service is
fine; the next command starts the new one.

The end-to-end test runs the built binary against a real registry and
systemd-machined, as root, on a host with systemd-nspawn:

```shell
NSPAWN=./target/release/nspawn sudo -E tests/e2e.sh
```

It exercises the whole tool: `hub ls`, `search` on the hub and on Docker Hub,
`login` and `logout`, a pull with both the `overlay` and the `flat` backend,
booting, `exec` through the PTY, volumes, the bridge network with names and
published ports between two machines, `create` from a local image, layer
sharing and garbage collection, an app from Docker Hub with entrypoint,
environment and volumes, `machinectl start` through the unit hooks, programs
that exit on their own or ignore their stop signal, and (when mkosi is
installed) a build, push and pull round trip. `NSPAWN_REGISTRY` (and
`NSPAWN_CA_CERT` for a private CA) must point at a registry that serves the
image named in `IMAGE`, `fedora:44` by default; the Docker Hub steps need
internet access.

Keep pull requests focused, add a unit test when the change has logic that can
be tested without a host, and run clippy before sending.

## Working on the images

The images are plain mkosi configuration trees. Changes to what the hub ships,
new distributions or releases go to
[mkosi-definitions](https://github.com/nspawn/mkosi-definitions). A definition
can be tried locally with `nspawn build -t test/NAME:1 DIRECTORY` before
sending it.

## Working on this site

The site is built with [Hugo](https://gohugo.io/) and the
[Docsy](https://www.docsy.dev/) theme. With Docker installed, a live preview
needs nothing else:

```shell
git clone https://github.com/nspawn/nspawn.org.git
cd nspawn.org
docker compose up
```

Then open <http://localhost:1313>. The container runs as uid and gid 1000; the
README of the repository explains how to pass yours if they differ. Without
Docker, install Node.js, Go and git and run `npm run install:safe` followed by
`npm run serve`. The pages are Markdown files under `content/en/`; every
documentation page has an "Edit this page" link that opens the file on GitHub.
