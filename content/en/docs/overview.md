---
title: Overview
weight: 1
description: >-
  What nspawn is, what it is not, and how images, machines, the hub and systemd
  fit together.
---

## What nspawn is

nspawn is a command line tool that manages
[systemd-nspawn](https://www.freedesktop.org/software/systemd/man/latest/systemd-nspawn.html)
machines with a docker-like workflow:

- Images are [OCI images](https://github.com/opencontainers/image-spec) that
  come from a registry. The default registry is the hub at `hub.nspawn.org`,
  where the nspawn.org team publishes images of common distributions built with
  [mkosi](https://github.com/systemd/mkosi). Docker Hub and any other registry
  work as well: `search` looks on the hub and on Docker Hub at once, and
  `login` keeps credentials per registry, the way `docker login` does.
- An image of the hub is verified against its signature before anything comes
  down; layers are downloaded once, verified against their digests and shared between
  the machines that use them. A machine's root file system is assembled from
  them by a [backend](/docs/images/#backends): an overlayfs mount, a native
  `systemd.mstack` directory, or a flat copy. `create` makes more machines from
  an image that is already local, without touching the registry.
- Machines are started, inspected and stopped through the D-Bus APIs of
  [systemd-machined](https://www.freedesktop.org/software/systemd/man/latest/systemd-machined.service.html)
  and of systemd itself. `machinectl` and `importctl` are never called, and
  every machine is an ordinary `systemd-nspawn@NAME.service` unit that
  `machinectl`, `systemctl` and `journalctl` see like any other. A drop-in makes that unit call nspawn before
  the machine starts, once it runs and after it ends, so `machinectl start`, a
  unit enabled at boot or a crash get the same network setup and cleanup as
  `nspawn start` and `nspawn stop`.
- The docker flags you know apply to any kind of machine: `-p` publishes
  ports, `-e` sets variables, `-v` mounts host directories or named volumes,
  `--entrypoint` and the arguments after `--` change what an app runs, `-l`
  labels it, `--restart` gives it a restart policy, `-m`, `--cpus` and
  `--pids-limit` bound its resources, `--health-cmd` probes it, `--secret`
  hands it a secret, `--depends-on` starts other machines before it, at boot
  as well, and `--hostname`, `-u`, `--cap-drop`, `--read-only`,
  `--tmpfs`, `--device`, `--dns`, `--add-host`, `--ulimit` and the rest of
  `docker run`'s flags mean what they mean there.
- `build` runs mkosi on a directory with a `mkosi.conf` and imports the result
  as a local image; `push` uploads an image to a registry, skipping the layers
  that are already there.
- `generate` prints the commands that make the same machines on another host,
  every flag they keep included.

The work is done by a service on the system bus, `org.nspawn`, and the command
line is one of its clients, the way `machinectl` and `systemctl` are clients of
machined and systemd. The service is started by the bus when a command arrives
and exits when it has been idle for a while; nothing runs in the background
otherwise. See [The service](#the-service).

It is one binary written in Rust. Its own state lives under `/var/lib/nspawn`,
the assembled machines under `/var/lib/machines`, and everything it generates on
the host is a plain systemd unit, drop-in or `.nspawn` settings file that you can
read.

## The service

Every command is a method call on `org.nspawn.Manager`: images, machines, the
network and credentials are methods, the long operations (pull, push, build,
create, rm, images rm, cp, volume rm and prune, network rm and prune) come back
as job objects that report their output and result, and `exec`, `logs`,
`events` and an attached `run` hand their streams or terminal over the bus,
with a process object that says how they ended. Scripts that would rather not speak
D-Bus get the same dictionaries as JSON from `inspect` and `--json` on the
listings.

Who may call what is polkit's answer, the way it is for machined and systemd.
The bus lets everyone in and the service asks polkit about the caller, under
two actions:

| Action | Methods |
| --- | --- |
| `org.nspawn.inspect` | The ones that only read: `images ls`, `ps` and `machines ls`, `inspect`, `generate`, `top`, `stats`, `events`, `network ls` and `network inspect`, `volume ls`, `secret ls` and `secret inspect`. |
| `org.nspawn.manage` | Everything else: pulling, building, starting, stopping, restarting, pausing, removing, `exec`, `shell`, `cp`, `logs`, volumes, secrets, the registry commands and the credentials. |

Both are for administrators by default, so `sudo nspawn ...` works as it always
did, and a desktop session (or a terminal where you started `pkttyagent`) is
asked for a password instead. Root is never asked, which is also how the
service keeps working where polkit is not installed: there, nobody but root can
call it. One interface asks nothing: `org.nspawn.Names` hands out the names of
machines, images, networks and volumes, and nothing else about them, to any
user.

To drive nspawn without a password, an administrator hands an action to a group
in a rule of their own. The packages ship one as an example in their
documentation directory; copy it to `/etc/polkit-1/rules.d/50-nspawn.rules`:

```javascript
polkit.addRule(function (action, subject) {
    if (action.id.startsWith("org.nspawn.") && subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
```

Everyone in that group can then run commands as root inside a machine and mount
any path of the host into one, which is to say they are administrators of the
host. Granting `org.nspawn.inspect` alone is the mild version: looking, without
touching.

A package installs the service; for a binary you built yourself,
`sudo nspawn daemon --install` writes the bus policy, the polkit actions, the
activation file and the unit, and tells systemd and the bus about them. Its journal is the usual one:

```shell
journalctl -u nspawn.service
```

## Machines and apps

nspawn tells two kinds of images apart when it installs them:

| Kind | What the image contains | How it runs |
| --- | --- | --- |
| **boot** | An init system (systemd) and no other entrypoint, like the hub images | Booted with `--boot`, as `machinectl start` does. `shell` opens machined's login session inside; `exec` enters the machine's namespaces and needs nothing from it. |
| **app** | Anything else, for example an image from Docker Hub | Its entrypoint runs under nspawn's stub init, with the environment, working directory, user and stop signal from the OCI config. Its network namespace is prepared by nspawn before the program starts, so the network is there from the first instruction. `exec` and `shell` enter the namespaces. |

The kind is detected at `pull` or `build` time and can be forced with
`--mode boot` or `--mode app`. Both kinds join the bridge network, are listed
by `ps`, stopped by `stop` and read by `logs`; the differences are described
in [Machines](/docs/machines/).

## Networking

Every machine joins `nspawn0`, a docker0 style bridge that nspawn manages
itself: fixed addresses, NAT, published ports (`-p 8080:80`) and a generated
`/etc/hosts` with the names of the other machines. `network create` makes
more networks like docker's user-defined ones, a machine may join several of
them with names of its own on each, `--network host` shares the host's network
instead, `--network none` gives a machine no network, and `--network veth`
gives booted machines the classic systemd-nspawn virtual ethernet pair
configured by systemd-networkd. See [Networking](/docs/networking/).

## The pieces

| Piece | Where | Role |
| --- | --- | --- |
| `nspawn` | [github.com/nspawn/nspawn](https://github.com/nspawn/nspawn) | The tool this documentation is about: the service and its command line. |
| The hub | `hub.nspawn.org` | An OCI registry with the images the team publishes. It is the default registry of the tool. |
| mkosi definitions | [github.com/nspawn/mkosi-definitions](https://github.com/nspawn/mkosi-definitions) | The public mkosi configuration the hub images are built from. |
| Blog | [blog.nspawn.org](https://blog.nspawn.org/) | Release notes and news. |

## What nspawn is not

- It is not a container runtime of its own: systemd-nspawn runs the machines,
  systemd supervises them, machined tracks them. nspawn only drives them, and
  its own service holds no machine open: it is started on demand and goes away
  again.
- It is not an orchestrator. There is no compose file, no service discovery
  beyond the names on the bridge, no scheduling.
- It does not build images by itself: `build` needs
  [mkosi](https://github.com/systemd/mkosi) installed on the host.
- It does not sign images: the hub's are signed by the workflow that builds
  them, and `pull` verifies one of those signatures before it downloads
  anything (see [Signed images](/docs/images/#signed-images)). Every blob is
  then checked against the sha256 digest in the manifest while it downloads,
  and registries are reached over HTTPS only.
