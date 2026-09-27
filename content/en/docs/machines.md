---
title: Machines
weight: 4
description: >-
  Starting and stopping machines, run like docker run, entrypoints,
  environment, volumes and labels, restart policies and resource limits,
  running commands inside, copying files, output, usage and events, removing
  machines, and how boot and app images differ.
---

Every one of these commands is a call to the
[service](/docs/overview/#the-service) on the system bus, which asks polkit
whether you may: `sudo` always works, and a rule can let your group through
without a password. The examples here use `sudo`.

Every machine nspawn starts is the systemd unit `systemd-nspawn@NAME.service`,
registered with systemd-machined under its name. `machinectl list`,
`machinectl status NAME`, `systemctl status systemd-nspawn@NAME` and
`journalctl -u systemd-nspawn@NAME` all work on it; nspawn adds the
docker-like commands on top.

The unit also carries a drop-in, `nspawn-hooks.conf`, that calls nspawn around
the machine's life: `ExecStartPre` prepares its network and settings,
`ExecStartPost` publishes its ports once it is registered, and `ExecStopPost`
releases everything however the machine ended. So `machinectl start NAME`,
`systemctl enable systemd-nspawn@NAME` for a machine that comes up at boot, a
program that exits on its own or a crash all behave like `nspawn start` and
`nspawn stop`. The drop-in names the nspawn binary that wrote it, which is why
nspawn belongs in `/usr/local/bin` or `/usr/bin`. It also carries the machine's
restart policy and resource limits, when it has them, and for an app machine
the `ExecStart=` that runs systemd-nspawn through `nspawn attach-exec`, which
is how `run -i` and `run -t` hand the program an input or a terminal.

## start

```shell
sudo nspawn start NAME [--network NETWORK]... [--network-alias [NETWORK=]NAME]...
                  [-p [IP:]HOST:CONTAINER[/udp]]... [--entrypoint PROGRAM] [-e VAR[=VALUE]]...
                  [-v SOURCE:TARGET[:ro]]... [-l KEY=VALUE]... [--restart POLICY] [-m SIZE]
                  [--cpus N] [--pids-limit N] [HEALTHCHECK OPTIONS] [OTHER OPTIONS]
                  [--secret NAME[:TARGET[:MODE[:UID:GID]]]]... [--image-command] [--no-wait]
                  [-- ARGUMENTS...]
```

`start` regenerates `/etc/systemd/nspawn/NAME.nspawn` from the machine's
record, sets up the [network](/docs/networking/) it is configured for, starts the
unit through systemd and waits up to 30 seconds for the machine to register
with machined. For a booted machine it then waits, up to 20 more seconds, until
the machine's own systemd is listening, so that a command can follow right
away; `--no-wait` skips that last wait. A program that runs and returns at once
is reported as such, not as a failure.

Everything given to `start` is remembered for the machine, so a plain
`nspawn start NAME` next time reuses the network, the ports, the command, the
variables and the volumes of the last run:

- `--network` switches the machine between the bridge, networks of its own
  made with `network create` (several at once, `--network-alias` giving it
  more names on them), a veth pair, the host's network and none; see
  [Networking](/docs/networking/).
- `-p [IP:]HOST:CONTAINER[/udp]` publishes a port on the host, on every
  address or on one, like docker. It needs a bridge network; `-p none` forgets
  all published ports.
- `--entrypoint`, `-e` and the arguments after `--` change what an **app**
  image runs; see [Command, entrypoint and environment](#command-entrypoint-and-environment).
  Boot images refuse them.
- `-v` mounts a host directory or a named volume into any kind of machine; see
  [Volumes](#volumes).
- `-l`/`--label`, `--restart`, `-m`, `--cpus` and `--pids-limit` label the
  machine, give it a restart policy and bound its resources; see
  [Labels](#labels) and [Restart policies and limits](#restart-policies-and-limits).
- `--health-cmd` and the other `--health-*` options give it a healthcheck, or
  replace the image's; see [Healthchecks](#healthchecks).
- `--hostname`, `-u`, `-w`, `--cap-add`, `--cap-drop`, `--privileged`,
  `--read-only`, `--tmpfs`, `--shm-size`, `--device`, `--dns`, `--dns-search`,
  `--add-host`, `--ulimit`, `--oom-score-adj`, `--stop-signal`,
  `--stop-timeout`, `--init` and `--sysctl` are the other flags of
  `docker run`; see [The other flags of docker run](#the-other-flags-of-docker-run).
- `--secret` hands it a secret as a file; see [Secrets](#secrets).

Machines are started by name. A reference (`fedora:44`, `docker.io/x`) is
refused with a hint to `pull` it or to `create` a machine from a local image.
Images that were not installed by nspawn, for example something created with
`machinectl import-tar`, can be started too: they get the stock template's veth
networking, and nspawn makes sure systemd-networkd runs on the host so that the
machine actually gets an address, but none of the flags above apply to them.

## run

```shell
sudo nspawn run [-d] [--rm] [-i] [-t] [OPTIONS] REFERENCE [COMMAND [ARGUMENT...]]
```

`run` makes a machine from an image and starts it, like `docker run`: `pull`,
or `create` from a local image with the same reference, then `start`, with the
options of both. What follows the image replaces an app's command, as with
docker. Without `-d` it stays with the machine:

- The machine's output follows until it ends, stdout and stderr together, a
  line at a time. It is read from the journal, so `nspawn logs NAME` shows it
  later, and the machine goes on should `run` be interrupted.
- `run` exits with the program's exit code, or 128 plus the signal it died of:
  130 after Ctrl-C, 137 after `kill`. Ctrl-C, SIGTERM, SIGHUP and SIGQUIT go to
  the program; a third Ctrl-C within a second leaves the machine running and
  returns.
- `-i` gives the program this standard input, `-t` a terminal; closing that
  terminal stops the machine, since nothing would read it any more.
- `--rm` removes the machine once it ends, and leaves nothing behind when the
  start fails. Named volumes stay, and so does an image the run had to pull,
  under the image's local name, as docker keeps images; without `--name` the
  machine gets a name of its own.

```shell
sudo nspawn run --rm docker.io/library/busybox:latest sh -c 'echo hi; exit 3'; echo $?
echo abc | sudo nspawn run -i --rm docker.io/library/busybox:latest wc -c
sudo nspawn run -it --rm docker.io/library/alpine:3 sh
sudo nspawn run -d --name web -p 8080:80 docker.io/library/nginx:latest
```

A booted image shows its console until it powers off (Ctrl-C powers it off).
`run -it` on one waits for its boot, opens a root shell and powers the machine
off when the shell ends, with the shell's exit code: `sudo nspawn run -it --rm
fedora:44` is a throwaway Fedora with its own systemd.

## Boot machines

A boot image is started with `Boot=yes`: systemd-nspawn runs the image's init
as PID 1, like `machinectl start` does, and the machine joins the bridge with
an address that its own systemd-networkd configures.

- `exec` enters the machine's namespaces directly, like `docker exec`, so
  nothing is needed inside: no D-Bus, no PAM. The exit code comes back and the
  program is found on the machine's `PATH`.
- `shell` opens machined's login session (`OpenMachineShell`), which needs
  D-Bus inside the machine; the hub images have it. Right after `start` the
  machine's D-Bus may not be up yet, so `shell` retries for up to 20 seconds
  instead of failing.
- `stop` asks machined to power the machine off and repeats the request every
  two seconds until the machine is gone, for up to a minute; the repetition
  covers the window right after boot in which the init has not installed its
  signal handlers yet. `--force` kills every process at once.
- With volumes, a small unit mounted into the machine, `nspawn-volumes.service`,
  holds `local-fs.target` until all of them are mounted, so services find their
  data in place whatever the backend.

## App machines

An app image is started with `Boot=no` and `ProcessTwo=yes`: nspawn's stub init
is PID 1 and the image's entrypoint runs under it, as its child, with the
environment, working directory, user and stop signal from the OCI config. Its
network namespace is built on the host before the program starts, so the
network is there from the first instruction, as in docker. For the same reason
an app on the bridge runs without a user namespace (`PrivateUsers=no`), which
is also docker's default; capabilities, seccomp and the other namespaces still
apply, and such an app keeps docker's default capabilities and `SYS_BOOT`,
with the kexec system calls filtered out, rather than systemd-nspawn's, whose `CAP_SYS_ADMIN` would be root on the host
outside a user namespace. `--cap-add` puts one back, `--privileged` all of
them.

- `exec` and `shell` enter the namespaces of the machine's leader process, on a
  pseudo terminal, with the image's environment. `shell` runs `/bin/sh`, and
  `-u USER` switches user for both.
- `stop` sends the image's stop signal (`StopSignal` in the config, `SIGTERM`
  by default, `--stop-signal` over it) to the program itself, waits `--timeout`
  seconds (the machine's `--stop-timeout`, else 10) and kills the machine if it
  is still there, like `docker stop`. A stop
  through systemd (`systemctl stop`, shutdown) reaches the stub init as a
  poweroff request, which it answers with `SIGTERM` to the program.
- A program that exits on its own ends the machine; its network and ports are
  released by the unit hooks, and `nspawn stop` on it afterwards only clears
  what it left behind and says `NAME was not running`.

## Command, entrypoint and environment

What an app runs is decided exactly as with docker:

- The arguments after `--` replace the image's `cmd` and follow its
  `entrypoint`. `nspawn start web -- nginx -T` still runs
  `/docker-entrypoint.sh` first, as `docker run nginx nginx -T` would.
- `--entrypoint PROGRAM` replaces the entrypoint with one program; the
  arguments after `--` follow it. `--entrypoint ""` drops the entrypoint, so
  the arguments run alone.
- Both are remembered, like the command of a docker container.
  `--image-command` forgets them and runs the image's own entrypoint and cmd
  again.
- `-e VAR=value` adds a variable on top of the image's, and `-e VAR` copies it
  from the shell that runs nspawn. The later value of a variable wins, `-e none`
  forgets them all, and `exec` sees the same environment as the program. Names
  follow the usual rules (letters, digits and `_`, not starting with a digit).
- The working directory, the user and the stop signal come from the image
  unless `-w`, `-u` and `--stop-signal` say otherwise. docker's `USER:GROUP`
  form is taken as docker takes it, from the image's config or from `-u`: the
  group, a name or a number, is the program's primary and only group. The user is resolved as
  docker resolves it, from the image's `passwd` and `group` files: systemd-nspawn
  asks `getent` inside the machine, which busybox lacks and musl's (alpine)
  cannot answer, so nspawn binds a stand-in that answers those lookups and
  hands any other to the image's own getent. A uid the `passwd` does not list
  runs all the same.

`ps` shows the effective command; `nspawn start NAME -- true` is a quick way to
check that an image runs at all.

## Volumes

```shell
sudo nspawn start web -v /srv/www:/usr/share/nginx/html:ro -v pgdata:/var/lib/postgresql
```

`-v SOURCE:TARGET[:ro]` is docker's syntax:

- An absolute `SOURCE` is a host directory (or file) that has to exist already,
  as with podman: `start` refuses a path that is not there rather than making
  one. A `SOURCE` without a leading `/` is a **named volume** that nspawn
  keeps under `/var/lib/nspawn/volumes/NAME`, created on first use with what
  the image has at `TARGET`, owner and files included, as docker seeds one
  (a program that runs as a user finds its data directory its own), and
  never deleted by `rm` or `images rm`. Names may contain letters, digits,
  `_`, `.` and `-`, and may not start with a dot.
- `TARGET` is an absolute path inside the machine, other than `/`. The same
  target cannot be mounted twice.
- `:ro` mounts it read-only; `:rw` is the default. Paths with whitespace are
  not supported.
- `-v` is repeatable and remembered; `-v none` forgets every volume.

In machines that run with private users (booted machines on overlay and flat,
which is the default), the mount is idmapped, so root inside owns what it
writes on the host, as docker users expect. On `mstack` machines nspawn attaches
the volumes from the host right after the machine's init starts, since
systemd-nspawn cannot idmap binds under managed user namespaces; that is what
`nspawn-volumes.service` waits for, for up to two minutes, failing visibly
otherwise. On overlay and flat the volumes come from the settings file and are
there before the init even runs.

Named volumes outlive the machines that use them. `nspawn volume ls` lists them
with the machines whose records mount them, `volume create NAME` makes one
ahead of its first use, and `volume rm` and `volume prune` remove the ones no
machine uses; a volume a machine still names is refused until that machine is
started with other volumes (or `-v none`) or removed.

## Labels

```shell
sudo nspawn start web --label caddy=web.example --label tier=front
```

Labels work as in docker. The image's own labels (`LABEL` in a Containerfile,
`OciLabels=` in a `mkosi.conf`) are read from its configuration when it is
pulled or built, and `-l`/`--label KEY=VALUE` on `start` or `create` adds the
machine's own on top, remembered like the ports; `--label none` forgets them.
nspawn does nothing with them itself: `nspawn inspect` and `ps --json` show the
merged `labels` and the image's `image_labels`, for tools that configure
themselves from them, a reverse proxy say.

## Restart policies and limits

```shell
sudo nspawn start web --restart unless-stopped -m 512m --cpus 1 --pids-limit 500
```

`--restart` takes docker's policies:

- `no`, the default: a machine that ends stays down.
- `on-failure`: restarted when its program, or its init, dies with an error.
- `always`: restarted whenever it ends, and started at boot.
- `unless-stopped`: like `always`, until `nspawn stop`, which also takes it
  off the boot list until the next `nspawn start`.

A machine that ends is started again after a second, then later and later, up
to half a minute, for as long as it keeps failing; `ps` shows it as
`restarting` meanwhile, and `nspawn stop` ends that. The ports, the address and
the volumes come back with it, since the unit's own hooks prepare every run.
`always` and `unless-stopped` enable the unit the way `machinectl enable` does,
and removing the machine takes that back. `machinectl stop` stops a machine for
good too, but does not take an `unless-stopped` one off the boot list, and a
`poweroff` from inside counts as ending under `always`.

`-m`/`--memory` (`512m`, `2g`), `--cpus` (`0.5`, `2`) and `--pids-limit` bound
the whole machine: they are the MemoryMax=, CPUQuota= and TasksMax= of its
unit, which is why nothing inside shows them. As with docker, `--memory` also
lets the machine use as much swap again (MemorySwapMax=), and no more. `0`
removes a limit.

Both are remembered like the ports and apply at the next start, and
`nspawn update` changes them without one, like `docker update`: a running
machine gets the new limits in its cgroup at once.

```shell
sudo nspawn update web -m 1g --cpus 2 --restart always
```

With a policy,
`stop --no-wait` of an app also lets systemd-nspawn's stub init send the
program SIGTERM and SIGHUP, since nobody stays behind to stop the unit later.

## Healthchecks

```shell
sudo nspawn start web --health-cmd "curl -fsS http://localhost/ || exit 1" --health-interval 10s --health-retries 3
```

Healthchecks are docker's. An image's `HEALTHCHECK` applies as it is, and
`--health-cmd` with `--health-interval`, `--health-timeout`,
`--health-retries`, `--health-start-period` and `--health-start-interval` on
`start`, `run`, `create` and `update` replace it; `--no-healthcheck` turns it
off. Durations are docker's (`10s`, `1m30s`, `500ms`), and so are the
defaults: 30 seconds between probes, 30 seconds for a probe, 3 failures in a
row before the machine is unhealthy, no start period, and 5 seconds between
probes during one.

The probe runs inside the machine through `/bin/sh -c` (`exit 0` is healthy),
from a unit of its own, `nspawn-health-NAME.service`, bound to the machine's
so that it goes with it. The machine is `starting` until a probe succeeds or
the start period ends, `healthy` after a success and `unhealthy` after the
retries fail in a row; a success brings it back.

- `ps` shows the health next to the state: `running (healthy)`,
  `running (unhealthy)`, `running (health: starting)`.
- `inspect` shows `health` with the status, the failing streak and the last
  five probes, each with its times, exit code and output, and `healthcheck`
  as it applies:

  ```text
  "health": "healthy",
  "healthcheck": {
    "interval": 2000000,
    "retries": 2,
    "start_interval": 0,
    "start_period": 0,
    "test": [
      "CMD-SHELL",
      "test -f /ok"
    ],
    "timeout": 0
  },
  ```
- `events` reports `health_status` with the new status on every change.
- `update` changes the healthcheck of a running machine at once, and the
  probes start afresh.

A stopped machine has no health, and neither has one without a healthcheck.

## The other flags of docker run

```shell
sudo nspawn start web --hostname web-1 -u nobody -w /tmp --cap-drop ALL --cap-add NET_BIND_SERVICE \
    --read-only --tmpfs /run:size=64m --tmpfs /tmp --shm-size 64m --device /dev/null:/dev/nullo \
    --dns 10.99.0.1 --dns-search example.test --add-host db:10.99.1.3 --add-host gw:host-gateway \
    --ulimit nofile=1024:4096 --oom-score-adj 500 --stop-signal SIGQUIT --stop-timeout 30 \
    --sysctl net.ipv4.icmp_echo_ignore_all=1
```

They mean what they mean to docker, are remembered like the rest and shown by
`inspect`. Each becomes a line of the machine's `.nspawn` settings file or of
its unit:

- `--hostname NAME`: the hostname inside, the machine's name by default. A
  booted machine gets it as its `/etc/hostname`, over the image's, since its
  systemd sets the hostname from that file.
- `-u USER[:GROUP]` and `-w DIR`: the user (a name or a uid, listed in the
  image's `passwd` or not, with a group of the image's `group` file or a gid
  after a colon, as docker's `--user` takes it; a group name the image lacks
  is refused) and the working directory the program runs with, instead of the
  image's. App images only.
- `--cap-add`, `--cap-drop` and `--privileged`: capabilities on top of, or
  out of, the default set (`NET_ADMIN` or `CAP_NET_ADMIN`; `ALL`): docker's
  (CHOWN, DAC_OVERRIDE, FOWNER, FSETID, KILL, MKNOD, NET_BIND_SERVICE,
  NET_RAW, SETFCAP, SETGID, SETPCAP, SETUID, SYS_CHROOT, AUDIT_WRITE) plus
  SYS_BOOT, so that a reboot from inside ends the machine, for an app on a
  bridge network, which runs without a user namespace, and systemd-nspawn's
  for a machine in one. An interface given with
  `--interface` keeps `NET_ADMIN` on its own. `--cap-drop ALL --cap-add
  NET_BIND_SERVICE` keeps that one, as with docker, and `--privileged` keeps
  every one.
- `--read-only`: the root read-only. `--tmpfs PATH[:OPTIONS]`: an empty tmpfs
  at a path (`size=64m`, `mode=1777`), which is how a read-only machine still
  writes `/tmp` or `/var/cache`. `/run` is a tmpfs of every machine already,
  so a `--tmpfs` that lands on it (`/var/run` in most images, docker's habit
  for a read-only nginx) is left out with a note. `--shm-size`: the size of
  `/dev/shm`.
- `--device HOST[:CONTAINER[:PERMISSIONS]]`: a device node of the host, bound
  into the machine and allowed to its cgroup (`r`, `w`, `m`; `rwm` by
  default), or a directory such as `/dev/dri`, whose nodes are allowed one by
  one. In a machine with private users the node keeps the host's
  ownership.
- `--dns` and `--dns-search`: the machine's `resolv.conf`, instead of the
  host's resolvers. `--add-host HOST:IP` (or `HOST=IP`, for an IPv6 address):
  lines for its `/etc/hosts`,
  `host-gateway` standing for the host's address on the machine's network.
- `--ulimit NAME=SOFT[:HARD]`: resource limits of the program (`nofile`,
  `nproc`, `core`, ...; `unlimited` is a value). `--oom-score-adj`: the
  machine's, -1000 to 1000.
- `--stop-signal` and `--stop-timeout`: what `stop`, `restart` and `kill` use
  for the machine instead of the image's stop signal and the default 10
  seconds; `-t` on `stop` still wins.
- `--init`: accepted for docker's sake; nspawn's stub init reaps orphans
  anyway. App images only.
- `--sysctl KEY=VALUE`: `net.*` keys, set in the network namespace nspawn
  makes for an app machine on a bridge network. Nothing else is accepted, and
  a booted machine sets its own.
- `--interface IFACE`: a network interface of the host, moved into the
  machine while it runs and back on the host when it stops, a wifi adapter
  with its whole phy included; no docker counterpart. See [Physical
  interfaces](/docs/networking/#physical-interfaces).

A list takes `none` to forget it (`--cap-drop none`, `--tmpfs none`), a value
an empty string (`--hostname ""`) or `0` (`--oom-score-adj 0`), and
`--privileged=false` and `--read-only=false` take those back. A path inside the
machine, the target of a volume or a secret, a `--tmpfs` or a `--device` path,
must be plain: a `.` or `..` component is refused, since it would land elsewhere
once mounted. A path the image
declares as a volume with nothing mounted over it gets a note at start: nspawn
has no anonymous volumes, so what is written there goes with the machine.

## Secrets

```shell
printf '%s' 'hunter2' | sudo nspawn secret create db-password
sudo nspawn start db --secret db-password -e POSTGRES_PASSWORD_FILE=/run/secrets/db-password
```

Secrets are docker's, without a swarm. `secret create NAME` reads the content
from standard input, or from `--file`, and keeps it encrypted with
`systemd-creds`, bound to the host's TPM2 where there is one and to its
credential key otherwise, under `/var/lib/nspawn/secrets`; `-l KEY=VALUE`
labels it. `--secret NAME` on `start`, `run` or `create` gives the machine the
plaintext at `/run/secrets/NAME`, a read-only file of root's with mode 0444;
`NAME:TARGET:MODE:UID:GID` chooses the path, mode and owner, as docker's long
form does. The file is decrypted when the machine starts, into a tmpfs of
root's alone, and gone when it stops.

`secret ls` lists the secrets with the machines that take them:

```text
 SECRET       SIZE  CREATED  USED BY
 db-password  7 B   9s ago   api
```

`secret inspect` prints what is known about them, never the content, and `secret rm`
removes the ones no machine takes; one a machine's record names is refused
until that machine is started with other secrets (or `--secret none`) or
removed. Secrets are not attached to `mstack` machines yet.

## ps

```shell
sudo nspawn ps [-a] [--json]      # same as: nspawn machines ls [-a] [--json]
```

```text
 MACHINE  IMAGE                             MODE  COMMAND                                   STATE              UP  PID     NETWORK                                                OS
 api      docker.io/library/busybox:latest  app   /bin/sh -c while true; do sleep 1; done   running            6s  895101  back:10.99.2.4                                         -
 db       docker.io/library/busybox:latest  app   /bin/sh -c while true; do sleep 1; done   running            8s  894865  back:10.99.2.2                                         -
 web      docker.io/library/busybox:latest  app   /bin/sh -c touch /ok; while true; do ...  running (healthy)  7s  894994  front:10.99.1.2 back:10.99.2.3 127.0.0.1:8080->80/tcp  -
```

`ps` lists every container machined knows about (the virtual machines it also
registers, libvirt's among them, are left out); machines that nspawn did not
install show `-` in the image columns. `-a` adds the nspawn machines that are
not running. `COMMAND` is the effective entrypoint and arguments of an app,
and `NETWORK` the machine's address on the default network, its other networks
as `NAME:ADDRESS`, and the published ports, or `host`, `veth`, `none` or
`container:NAME`. A
machine between two runs of its restart policy is listed as `restarting` even
without `-a`, a frozen one as `paused`, and a healthcheck follows the state:
`running (healthy)`.

`ps --json` prints the same machines as the service returns them, each with its
whole record, and `nspawn inspect NAME...` prints one or more machines, running
or not, as a JSON array, like `docker inspect`: what a script or an agent
reads.

## exec and shell

```shell
sudo nspawn exec MACHINE [-u USER] [-e VAR[=VALUE]]... [-w DIR] [-T] [-t] [-i] [-d] COMMAND...
sudo nspawn shell MACHINE [-u USER]
```

`exec` runs one command inside a running machine of either kind, on a terminal
when standard input and output are both one, and exits with the command's status, so it works in scripts and
pipelines (what goes through stdin and stdout is byte exact). The program is
looked up on the machine's `PATH`, the image's environment and the `-e`
variables of the machine apply, and the working directory is the machine's.
Neither D-Bus nor anything else is needed inside. The command runs with the
machine's capabilities and resource limits, like the machine's own processes;
right after a start it waits, a few seconds at most, until systemd-nspawn has
finished confining the machine. The flags are `docker exec`'s: `-u USER[:GROUP]`
takes names or numbers of the image's passwd and group files (with a group, that
one is the only group), `-e` adds variables for this command, `-w` a working directory, `-T` refuses a
terminal even from one (pipes, as in a script) and `-t` asks for one even
without, `-i` is accepted for docker's sake, and `-d` leaves the command
running in the background and returns at once.

`shell` opens an interactive shell as `root` (or `-u USER`): machined's login
session for booted machines, `/bin/sh` in the machine's namespaces for apps.

## cp

```shell
sudo nspawn cp ./nginx.conf web:/etc/nginx/
sudo nspawn cp web:/var/log/nginx ./nginx-logs
sudo nspawn cp ./site/. web:/usr/share/nginx/html
```

`cp` copies files and directories between the host and a machine, running or
not, with docker cp's rules:

- An existing directory as the destination receives the source under its own
  name; anything else is the name of the copy. A destination ending in `/`
  has to be a directory.
- `DIR/.` copies the contents of DIR rather than DIR.
- What goes in belongs to root inside the machine, whatever user namespace it
  runs in; what comes out belongs to whoever ran `cp`. Modes and modification
  times are kept.
- Paths inside the machine are resolved inside it, so a link there, absolute
  or not, never leads to the host. Links are copied as links; devices, sockets
  and fifos are left out, and so are the kernel's file systems mounted inside
  a running machine (`/proc`, `/sys` and the like).

A stopped overlay or flat machine can be copied into and out of; a stopped
`mstack` machine cannot, since its tree only exists while it runs. Where
SELinux enforces, a host directory mounted with `-v` keeps its own label, which
the service may not be allowed to write to (docker needs `:z` for the same);
named volumes are nspawn's own and always work.

## logs

```shell
sudo nspawn logs MACHINE... [-f] [-n N] [--since WHEN] [--until WHEN] [-t] [--all] [--inside]
```

systemd-nspawn sends what the machine writes to its console to the journal of
`systemd-nspawn@MACHINE.service`, and `logs` reads it with `journalctl`. By
default only the machine's own output is shown, from every run of the unit,
earlier ones included:

- `-f` keeps printing new output, starting from the last 10 lines unless `-n`
  says otherwise. `-n N` shows the last N lines; `--since "10 min ago"` and
  `--until` accept anything `journalctl` does, and nothing is followed past
  `--until`; `-t` prefixes each line with its timestamp.
- Several machines at once are shown together, every line behind its
  machine's name (`web | ...`), the way docker compose shows them.
- `--all` also shows what systemd logged about the unit: start, stop,
  failures.
- `--inside` reads the journal of a **booted** machine itself
  (`journalctl --machine`), which is where the services running inside log.

`logs` works for stopped machines too, since the journal keeps what they wrote.

## stats

```shell
sudo nspawn stats [NAME...] [--no-stream] [--json]
```

`stats` shows what each running machine uses, like `docker stats`, drawn again
every second: CPU (100% is one CPU busy), memory in use against the limit (the
host's memory without one), network and disk traffic, and processes. The
numbers are those of the cgroup of the machine's unit, which holds the whole
machine, and of its interfaces as the machine sees them. `--no-stream` prints
one table, `--json` one object per machine and reading.

```text
 NAME  CPU %  MEM USAGE / LIMIT  MEM %  NET I/O      BLOCK I/O      PIDS
 api   0.00%  2.4 MiB / 3.8 GiB  0.06%  372 B / 0 B  0 B / 4.0 KiB  3
 db    0.00%  2.4 MiB / 3.8 GiB  0.06%  892 B / 0 B  0 B / 4.0 KiB  3
 web   0.00%  2.4 MiB / 3.8 GiB  0.06%  522 B / 0 B  0 B / 4.0 KiB  3
```

## events

```shell
sudo nspawn events [--since WHEN] [--until WHEN] [-f KEY=VALUE]... [--json]
```

`events` reports what happens, like `docker events`: machines that start, die
(with their exit code), stop, are restarted, run out of memory, fail or change
health (`health_status`), and what nspawn does: pulls, builds, creations,
pushes, kills, updates and removals, of networks, volumes and secrets too. It
reads the journal, where systemd logs every start and end of a machine's unit
however it was started, and nspawn logs what it does, so `--since` reads past
events back. Filters take `name=`, `type=` (`machine`, `network`, `volume`,
`secret`), `event=` and `label=KEY` or `label=KEY=VALUE`: the same key given
twice matches either value, different keys must all match. `--json` prints one
object per event.

```text
2026-09-24T20:44:51.767425Z network create backend (interface=nsbr-backend, internal=false, subnet=10.99.1.0/24)
2026-09-24T20:44:53.691583Z machine start db (image=docker.io/library/busybox:latest)
2026-09-24T20:44:56.730139Z machine create busybox (from=api, reference=docker.io/library/busybox:latest)
2026-09-24T20:44:57.105739Z machine start busybox
2026-09-24T20:44:57.125181Z machine die busybox (code=exited, exit_code=3)
2026-09-24T20:44:57.154522Z machine fail busybox (result=exit-code)
2026-09-24T20:44:57.381848Z machine remove busybox (image=docker.io/library/busybox:latest)
2026-09-24T20:44:57.645267Z machine kill api (image=docker.io/library/busybox:latest, signal=1)
2026-09-25T10:20:16.502186Z machine health_status web (image=docker.io/library/busybox:latest, status=healthy)
```

Times are in UTC. A machine's `die` carries the exit code systemd-nspawn gave:
255 for an app whose program died of a signal, as `stop` makes it. Every event
of a kind carries the same metadata whatever the action, so a `remove` says as
much as a `create`: `image=` on a machine's, `subnet=`, `interface=` and
`internal=` on a network's, `path=` on a volume's, `size=` on a secret's.

## stop

```shell
sudo nspawn stop NAME... [-f] [-t SECONDS] [--no-wait]
```

Stops the machines as described above for boot and app machines, one after
the other, waits until each is gone (a minute at most for a booted machine),
stops the unit so that the image can be removed right away, clears the failure
a signal-killed program leaves on the unit, releases the firewall exceptions
of a veth machine and removes the machine's published ports and network
namespace. `--no-wait` returns right after the request, without the kill after
`--timeout` (the machine's `--stop-timeout`, else 10 seconds); the unit hooks
release the network when the machine ends. `-f` kills every process at once,
like `docker kill`. Stopping a machine that already ended is not an error, and
a paused machine is thawed first.
With a restart policy the machine stays stopped for now: an `unless-stopped`
machine is also taken off the boot list until the next `start`, while an
`always` one still starts at the next boot.

## restart

```shell
sudo nspawn restart NAME... [-t SECONDS]
```

`restart` is a `stop` followed by a `start` with everything the machine
remembers, like `docker restart`; a machine that is not running is started.
`-t` is `stop`'s.

## pause and unpause

```shell
sudo nspawn pause NAME...
sudo nspawn unpause NAME...
```

`pause` freezes every process of a machine through the cgroup freezer of its
unit, like `docker pause`, and `unpause` thaws them. `ps` shows a frozen
machine as `paused`; `stop` and `kill` thaw it first.

## top

```shell
sudo nspawn top MACHINE
```

```text
 PID     USER  TIME      COMMAND
 894994  root  00:00:00  (sd-stubinit)
 895009  root  00:00:00  /bin/sh -c touch /ok; while true; do sleep 1; done
 895198  root  00:00:00  sleep 1
```

`top` lists the processes of a running machine, like `docker top`: the PID as
the host sees it, the user as the machine sees it, CPU time and command, read
from the machine's cgroup and PID namespace.

## kill

```shell
sudo nspawn kill web                 # SIGKILL: stopped for good
sudo nspawn kill -s HUP web          # a signal for the program
```

`kill` sends a signal to machines, like `docker kill`. SIGKILL, the default,
stops the machine for good, as `stop --force` does. Any other signal goes to
the program of an app, or to the init of a booted machine, and the machine
lives on unless it ends of it; then its restart policy applies, except when the
signal was the machine's own stop signal, which counts as a stop, as with
docker.

## rm

```shell
sudo nspawn rm web2
sudo nspawn rm -f web        # stop it first, like docker rm -f
```

`rm` removes a machine: its record, its tree, its unit files, the boot link a
restart policy made, and the layers nobody else uses. A pulled image is a
machine too, so `rm` and `images rm` remove the same thing; `rm -f` stops a
running machine first where both refuse otherwise. Named volumes are kept, and
`rm` says which.
