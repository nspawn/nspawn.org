---
title: Getting started
weight: 2
description: >-
  Requirements, installation, a first machine pulled from the hub and an app
  from Docker Hub.
---

## Requirements

- A host with **systemd-nspawn** and **systemd-machined**, version **255 or
  newer** (255, 259 and 262 are the ones the test suite runs against; 252 cannot
  mount the files nspawn generates under a machine's `/run`). cgroup v2 is
  required.
- **overlayfs** on **Linux 6.5 or newer** for the `overlay` backend, which is
  the default and what app images always use (the layers are mounted with
  `lowerdir+=`). Without it images are extracted as flat directories.
- **iproute2** and **nftables** (`ip` and `nft`) for the bridge network. Nothing
  else: the bridge does not need systemd-networkd or NetworkManager on the host.
  Only `--network veth` needs systemd-networkd, and only `--interface` with a
  wifi adapter needs `iw` (for an app on the bridge) or systemd 256 (for a
  booted machine).
- **Root, or an administrator with polkit.** Every command is a call to the
  [service](/docs/overview/#the-service) on the system bus, which asks polkit
  who you are: root is never asked, an administrator is asked for a password,
  and a polkit rule can hand the actions to a group. The examples below use
  `sudo`, which works everywhere, including hosts without polkit.
- **D-Bus inside a booted machine** for `shell`, which uses machined's login
  session; the hub images have it. `exec` enters the machine's namespaces and
  needs nothing inside.
- **polkit** if anyone other than root is to run the commands. The packages
  recommend it; without it the service answers root alone.
- **mkosi** only if you want to [build images](/docs/building/).

## Installation

A package brings the binary and the service it runs as. Every
[release](https://github.com/nspawn/nspawn/releases) carries an RPM for Fedora,
a package for Arch, a `.deb` built on Ubuntu 24.04 that also fits later Debian
and Ubuntu releases, the plain binary in a tarball, and a `SHA256SUMS` over all
of them. On Arch Linux the AUR has two packages as well:
[nspawn](https://aur.archlinux.org/packages/nspawn), built from the latest
release, and [nspawn-git](https://aur.archlinux.org/packages/nspawn-git), from
the latest commit on `master`.

On Fedora or RHEL with SELinux enforcing, the `nspawn-selinux` package carries
the domain the service runs in; the RPM recommends it, so a plain `dnf install`
of the package brings it along. Without it the service runs unconfined and the
bus drops it when it passes a descriptor, which is what `exec`, `shell`,
`logs` and `cp` do: the rest of the commands work either way.

To build it yourself you need a Rust toolchain of version 1.85 or newer:

```shell
git clone https://github.com/nspawn/nspawn.git
cd nspawn
cargo build --release
sudo install -Dm755 target/release/nspawn /usr/local/bin/nspawn
sudo nspawn daemon --install
nspawn --version
```

`daemon --install` writes the bus policy, the polkit actions, the activation
file and the unit that let the bus start the service on demand, naming the
binary you just installed; a package does the same for you. Install the binary
in `/usr/local/bin` or `/usr/bin`, not below a home directory: the unit of every
machine calls nspawn by the path it was installed from, and on SELinux hosts a
system service is refused a binary under `/home`.

On a host with SELinux enforcing, a binary installed by hand keeps the label of
where it sits, and a service that is not `nspawn_exec_t` runs unconfined, so
`exec`, `shell`, `logs` and `cp` fail with the client disconnected. `daemon --install`
says so, and this is the fix:

```shell
sudo semanage fcontext -a -t nspawn_exec_t /usr/local/bin/nspawn
sudo restorecon -v /usr/local/bin/nspawn
```

The packages install into `/usr/bin`, which their policy already labels.

## A first machine

Find an image. `search` asks the hub and Docker Hub and prints, for every hit,
the reference `pull` takes:

```shell
sudo nspawn search fedora
```

```text
 SOURCE          NAME                      DESCRIPTION                           STARS  OFFICIAL
 hub.nspawn.org  fedora                    tags: 43, 44, latest, rawhide         -      -
 hub.nspawn.org  fedora-devel              tags: 44, latest                      -      -
 Docker Hub      docker.io/library/fedora  Official Docker builds of Fedora      1300   yes
 ...
```

Pull one. References without a registry part go to the hub, and the local name
is derived from the reference unless you pass `--name`:

```shell
sudo nspawn pull fedora:44
```

```text
hub.nspawn.org/fedora:44: signature verified (key 6wiWMtJZCUkV, keyless https://github.com/nspawn/mkosi-definitions/.github/workflows/mkosi.yml@refs/heads/master)
hub.nspawn.org/fedora:44: manifest 9240778b2c77 with 1 layer(s), assembling as overlay
blob f0c1e88e32b3: downloading
blob 28edf9a59c17: downloading
blob f0c1e88e32b3: downloaded
blob 28edf9a59c17: downloaded
image fedora-44 (boot image) is ready: nspawn start fedora-44
```

The image's signature was checked first (every image on the hub is signed by
the workflow that builds it; see [Signed images](/docs/images/#signed-images)),
then the blobs went to `/var/lib/nspawn`, the root file system of the machine is
mounted at `/var/lib/machines/fedora-44`, `/etc/systemd/nspawn/fedora-44.nspawn`
holds the settings nspawn boots it with, and a drop-in of
`systemd-nspawn@fedora-44.service` makes the unit call nspawn around its life.

```shell
sudo nspawn start fedora-44
sudo nspawn ps
```

```text
 MACHINE    IMAGE                     MODE  COMMAND  STATE    UP   PID    NETWORK    OS
 fedora-44  hub.nspawn.org/fedora:44  boot  init     running  12s  48213  10.99.0.2  Fedora Linux 44 (Forty Four)
```

`start` returns once the machine's own systemd is up, so a command can follow
right away. `exec` runs it inside and brings back its exit code; `shell` opens
a login session as root:

```shell
sudo nspawn exec fedora-44 -- systemctl is-system-running
sudo nspawn shell fedora-44
```

The hub images log in as `root` without a password on the console. What the
machine printed is in `logs`, and `--inside` reads the journal of the machine
itself:

```shell
sudo nspawn logs fedora-44
sudo nspawn logs fedora-44 --inside -n 50
```

Stop it and, when you no longer need it, remove it. Removing an image also frees
the layers and blobs that no other image references:

```shell
sudo nspawn stop fedora-44
sudo nspawn images rm fedora-44
```

## An app from Docker Hub

Images without an init system run as apps: the entrypoint from the image runs
under a stub init, on the bridge like any other machine, so `-p` publishes its
ports on the host:

```shell
sudo nspawn search nginx --source dockerhub
sudo nspawn pull docker.io/library/nginx:latest --name web
sudo nspawn start web -p 8080:80
curl -sI http://localhost:8080/ | head -1
sudo nspawn logs web -f
sudo nspawn stop web
```

`sudo nspawn run -d docker.io/library/nginx:latest --name web -p 8080:80` does
the pull and the start in one step, like `docker run -d`. Without `-d`, `run`
stays attached as `docker run` does: `sudo nspawn run -it --rm
docker.io/library/alpine:3 sh` gives you a shell in a machine that goes away
when you leave it. The port and any other flag given to `start` or `run` are
remembered, so the next `sudo nspawn start web` publishes it again. `stop` sends the image's stop
signal (`SIGQUIT` for nginx) to the program and kills the machine after ten
seconds if it is still there; `-t` changes the grace period.

Docker Hub limits anonymous pulls per address. `sudo nspawn login docker.io -u USER`
keeps your credentials for that registry only; see
[Registries and credentials](/docs/images/#registries-and-credentials).

## Next steps

- [Images and the hub](/docs/images/): references, search, credentials, backends,
  boot and app detection, `create`, where things are stored.
- [Machines](/docs/machines/): `start`, `run`, `stop`, `kill`, `exec`,
  `shell`, `logs`, `ps`, `stats`, `events`, entrypoints, environment and
  volumes.
- [Networking](/docs/networking/): the bridge, networks of your own, published
  ports, veth and host networking, firewalls.
- [Building images](/docs/building/): `build` and `push`.
- [Configuration](/docs/configuration/): `/etc/nspawn/nspawn.toml`, environment
  variables and flags.
