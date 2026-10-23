---
title: Machines
weight: 4
description: >-
  Starting and stopping machines, run like docker run, how boot and app images
  differ, volumes, restart policies and limits, healthchecks, dependencies,
  GPUs, secrets, the commands for machines, and making them again elsewhere.
---

Every one of these commands is a call to the
[service](/docs/overview/#the-service) on the system bus, which asks polkit
whether you may: `sudo` always works, and a rule can let your group through
without a password. The examples here use `sudo`.

Every machine nspawn starts is the systemd unit `systemd-nspawn@NAME.service`,
registered with systemd-machined under its name. `machinectl list`,
`machinectl status NAME`, `systemctl status systemd-nspawn@NAME` and
`journalctl -u systemd-nspawn@NAME` (with `--namespace=nspawn` for what the
machine prints, see [logs](#logs)) all work on it; nspawn adds the
docker-like commands on top.

The unit also carries a drop-in, `nspawn-hooks.conf`, that calls nspawn around
the machine's life: `ExecStartPre` prepares its network and settings,
`ExecStartPost` publishes its ports once it is registered, and `ExecStopPost`
releases everything however the machine ended; a machine with
[dependencies](#dependencies) first waits for them in another `ExecStartPre`.
So a start by `machinectl start NAME` or at boot (`systemctl enable
systemd-nspawn@NAME`) prepares the machine as `nspawn start` does, and a program
that exits or crashes is cleaned up after as `nspawn stop` would. The drop-in
names the nspawn binary that wrote it, which is why nspawn belongs in
`/usr/local/bin` or `/usr/bin`. It also carries the machine's restart policy and
resource limits, when it has them, and, for an app machine and for a booted one
whose output goes to nspawn's journal (the default), the `ExecStart=` that runs
systemd-nspawn through `nspawn attach-exec`, which is how `run -i` and `run -t`
hand the program an input or a terminal and how the output reaches that
journal.

## start

```shell
sudo nspawn start NAME [--network NETWORK]... [--network-alias [NETWORK=]NAME]...
                  [-p [IP:]HOST:CONTAINER[/udp]]... [--entrypoint PROGRAM] [-e VAR[=VALUE]]...
                  [-v SOURCE:TARGET[:ro]]... [-l KEY=VALUE]... [--restart POLICY] [-m SIZE]
                  [--cpus N] [--pids-limit N] [HEALTHCHECK OPTIONS] [OTHER OPTIONS]
                  [--secret NAME[:TARGET[:MODE[:UID:GID]]]]... [--depends-on NAME[:CONDITION][:optional]]...
                  [--env-file FILE]... [--label-file FILE]... [--mount type=TYPE,...]...
                  [--ip [NETWORK=]ADDRESS] [--gpus GPUS] [--image-command] [--no-wait] [-- ARGUMENTS...]
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
  more names on them), a veth pair, the host's network, another machine's
  (`container:NAME`) and none, and `--ip`
  fixes its address on one made with `network create`; see
  [Networking](/docs/networking/).
- `-p [IP:]HOST:CONTAINER[/udp]` publishes a port on the host, on every
  IPv4 and IPv6 address or on one, like docker. It needs a bridge network;
  `-p none` forgets all published ports.
- `--entrypoint`, `-e`, `--env-file` and the arguments after `--` change what
  an **app** image runs; see [Command, entrypoint and environment](#command-entrypoint-and-environment).
  Boot images refuse them.
- `-v` mounts a host directory or a named volume into any kind of machine, and
  `--mount` is its long form; see [Volumes](#volumes).
- `-l`/`--label`, `--label-file`, `--restart`, `-m`, `--memory-swap`, `--cpus` and
  `--pids-limit` label the machine, give it a restart policy and bound its
  resources; see
  [Labels](#labels) and [Restart policies and limits](#restart-policies-and-limits).
- `--health-cmd` and the other `--health-*` options give it a healthcheck, or
  replace the image's; see [Healthchecks](#healthchecks).
- `--hostname`, `-u`, `-w`, `--cap-add`, `--cap-drop`, `--privileged`,
  `--read-only`, `--tmpfs`, `--shm-size`, `--device`, `--dns`, `--dns-search`,
  `--add-host`, `--ulimit`, `--oom-score-adj`, `--stop-signal`,
  `--stop-timeout`, `--init` and `--sysctl` are the other flags of
  `docker run`, `--log-driver` where the program's output goes, and
  `--timezone` how systemd-nspawn sets
  `/etc/localtime`; see [The other flags of docker run](#the-other-flags-of-docker-run).
- `--secret` hands it a secret as a file; see [Secrets](#secrets).
- `--gpus` and `--device VENDOR/CLASS=NAME` hand it devices of the host's CDI
  specs; see [GPUs and CDI devices](#gpus-and-cdi-devices).

Machines are started by name. A reference (`fedora:44`, `docker.io/x`) is
refused with a hint to `pull` it or to `create` a machine from a local image.
Images that were not installed by nspawn, for example something created with
`machinectl import-tar`, can be started too: they get the stock template's veth
networking, and nspawn starts systemd-networkd on the host when the host has no
`.network` files of its own (see [veth](/docs/networking/#veth)); the flags above
are refused for them.

## run

```shell
sudo nspawn run [-d] [--rm] [-i] [-t] [OPTIONS] REFERENCE [COMMAND [ARGUMENT...]]
```

`run` makes a machine from an image and starts it, like `docker run`: `pull`,
or `create` from a local image with the same reference, then `start`, with the
options of both. A name without a registry is looked for here under the
configured registry, then as Docker Hub's (`app` as `docker.io/library/app`,
the name of an image compose pulled from Docker Hub), and only then pulled from
the configured registry.
What follows the image replaces an app's command, as with docker; one that
starts with a dash comes after `--`. Without `-d` it stays with the machine:

- The machine's output follows until it ends, stdout and stderr together, a
  line at a time. It is read from the journal (nspawn's own, or the system's with
  `--log-driver journal`), so `nspawn logs NAME` shows it later, and the machine
  goes on should `run` be interrupted. With `--log-driver none` it comes straight
  from the program and nothing is kept.
- `run` exits with the program's exit code, or, for a program under the stub
  init, 128 plus the signal nspawn sent it: 130 after Ctrl-C, 137 after `kill`.
  A signal from elsewhere (a crash, a kill from inside the machine, Ctrl-C with
  `-t`) gives 255 there. A program that is PID 1 ends with 1 whatever signal
  killed it but `kill`'s SIGKILL (137), which is how systemd-nspawn ends then.
  Ctrl-C, SIGTERM, SIGHUP and SIGQUIT go to the program; a third Ctrl-C within a
  second leaves the machine running and returns.
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

An app image is started with `Boot=no` and `ProcessTwo=yes`: systemd-nspawn's
stub init is PID 1 and the image's entrypoint runs under it, as its child, with
the environment, working directory, user and stop signal from the OCI config.
Its network namespace is built on the host before the program starts, so the
network is there when it starts, as in docker.

A user namespace cannot join a network namespace that belongs to the host, so an
app on a bridge network runs without one (`PrivateUsers=no`), as docker runs
containers by default. Capabilities, seccomp and the other namespaces still
apply. Such an app gets docker's default capabilities plus `SYS_BOOT`, with the
kexec system calls filtered out. It does not get systemd-nspawn's set: its
`CAP_SYS_ADMIN` outside a user namespace is root on the host. `--cap-add` puts
one back, `--privileged` all of them.

An image that carries s6-overlay (linuxserver.io's images, Home Assistant's and
others) runs with its `/init` as PID 1 of the machine, as s6 requires and as
docker runs every program: `ProcessTwo=` is left out and the stop signal becomes
systemd-nspawn's `KillSignal=`.
`--init=false` asks the same of any app, and `--init` puts the program back
under the stub init. A program that is PID 1 ignores the signals it has no
handler for, as under docker, so `stop` kills it after its timeout when it does
not handle its stop signal.

- `exec` and `shell` enter the namespaces of the machine's leader process, on a
  terminal when standard input and output are one, with the image's
  environment. `exec` runs as the machine's
  user, `shell` runs `/bin/sh` as root, and `-u USER` switches user for both.
- `stop` sends the image's stop signal (`StopSignal` in the config, `SIGTERM`
  by default, `--stop-signal` over it) to the program itself, waits `--timeout`
  seconds (the machine's `--stop-timeout`, else 10) and kills the machine if it
  is still there, like `docker stop`. A stop through systemd (`systemctl stop`,
  shutdown) reaches the stub init as a poweroff request, which it answers with
  SIGTERM and SIGHUP to the program.
- A program that exits on its own ends the machine; its network and ports are
  released by the unit hooks, and `nspawn stop` on it afterwards only clears
  what it left behind and says `NAME was not running`.

## Command, entrypoint and environment

What an app runs is decided exactly as with docker:

- The arguments after `--` replace the image's `cmd` and follow its
  `entrypoint`. `nspawn start web -- nginx -T` still runs
  `/docker-entrypoint.sh` first, as `docker run nginx nginx -T` would.
- `--entrypoint PROGRAM` replaces the entrypoint with one program and drops the
  image's `cmd`, so only the arguments after `--` follow it (`--entrypoint
  /bin/sh` alone is a shell). `--entrypoint ""` drops the entrypoint, so the
  arguments run alone. An app left with nothing to run is refused with
  docker's `no command specified`.
- Both are remembered, like the command of a docker container.
  `--image-command` forgets them and runs the image's own entrypoint and cmd
  again.
- `-e VAR=value` adds a variable on top of the image's, and `-e VAR` copies it
  from the shell that runs nspawn. `--env-file FILE` reads `KEY=VALUE` lines as
  docker reads them (no quoting, no expansion, `#` comments), before the `-e`
  that follow. The later value of a variable wins, `-e none` forgets them all,
  and `exec` sees the same environment as the program. Any name but an empty
  one is taken (`discovery.type`, as Elasticsearch reads it).
- The working directory, the user and the stop signal come from the image
  unless `-w`, `-u` and `--stop-signal` say otherwise. The user and group are
  resolved from the image's `passwd` and `group` files, as docker resolves them.
  With `USER:GROUP`, from the image's config or from `-u`, the group (a name or a
  number) is the program's primary and only group. systemd-nspawn asks `getent`
  inside the machine, which busybox lacks and musl cannot answer, so nspawn binds
  a stand-in that answers these lookups and passes others to the image's own
  getent. An image without a shell (distroless, scratch) gets a small program
  instead, so `-u 1000:1000` works there too. A uid missing from `passwd` runs
  with group 0 and `/` as home.

`ps` shows the effective command; `nspawn run --rm IMAGE true` is a quick way to
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
- `--mount type=bind|volume|tmpfs,source=...,target=...` is the long form of
  `-v` and `--tmpfs` (`readonly`, `tmpfs-size`, `tmpfs-mode`); a volume needs
  its name, since nspawn has no anonymous volumes.

In machines that run with private users (every machine but an app on a bridge
network or in another machine's network), the mount is idmapped, so a file root
writes inside belongs to root on the host, as docker users expect. On `mstack` machines nspawn attaches
the volumes from the host right after the machine's init starts, since
systemd-nspawn cannot idmap binds under managed user namespaces; that is what
`nspawn-volumes.service` waits for, for up to two minutes, failing visibly
otherwise. On overlay and flat the volumes come from the settings file and are
there before the init even runs.

Named volumes outlive the machines that use them. `nspawn volume ls` lists them
with the machines whose records mount them, `volume create NAME` makes one
ahead of its first use (filled from the image of the first machine that takes it
while it is empty), and `volume rm` and `volume prune` remove the ones no
machine uses; a volume a machine still names is refused until that machine is
started with other volumes (or `-v none`) or removed.

## Labels

```shell
sudo nspawn start web --label caddy=web.example --label tier=front
```

Labels work as in docker. The image's own labels (`LABEL` in a Dockerfile,
`OciLabels=` in a `mkosi.conf`) are read from its configuration when it is
pulled or built, and `-l`/`--label KEY=VALUE` on `start`, `run` or `create` adds the
machine's own on top, remembered like the ports; `--label-file FILE` reads
them from a file of `KEY=VALUE` lines, and `--label none` forgets them.
nspawn does nothing with them itself: `nspawn inspect` and `ps --json` show the
merged `labels` and the image's `image_labels`, for tools that configure
themselves from them, a reverse proxy say.

## Restart policies and limits

```shell
sudo nspawn start web --restart unless-stopped -m 512m --cpus 1 --pids-limit 500
```

`--restart` takes docker's policies:

- `no`, the default: a machine that ends stays down.
- `on-failure`: restarted when its program, or its init, dies with an error;
  `on-failure:N` is accepted, but the count is ignored: systemd restarts on every
  failure.
- `always`: restarted whenever it ends, and started at boot.
- `unless-stopped`: like `always`, until `nspawn stop`, which also takes it
  off the boot list until the next `nspawn start`.

A machine that ends is started again after a second, then later and later, up
to half a minute, for as long as it keeps failing; `ps` shows it as
`restarting` meanwhile, and `nspawn stop` ends that. The ports, the address and
the volumes come back with it, since the unit's own hooks prepare every run.
`always` and `unless-stopped` enable the unit the way `machinectl enable` does,
and removing the machine takes that back. `machinectl stop` stops a machine for
good too, but does not take an `unless-stopped` one off the boot list. A
`poweroff` inside the machine is an ending like any other, which `always` and
`unless-stopped` restart.

`-m`/`--memory` (`512m`, `2g`), `--cpus` (`0.5`, `2`) and `--pids-limit` bound
the whole machine: they are the MemoryMax=, CPUQuota= and TasksMax= of its
unit, which is why nothing inside shows them. As with docker, `--memory` also
lets the machine use as much swap again (MemorySwapMax=), and no more, unless
`--memory-swap` gives memory and swap together, as docker takes it: equal to
`--memory` for no swap, larger for the difference, `-1` for swap without a
bound. `0` removes a limit, and brings `--memory-swap` back to its default.

The restart policy and the limits are remembered like the ports and apply at
the next start, and
`nspawn update` changes them without one, like `docker update`: a running
machine gets the new limits in its cgroup at once.

```shell
sudo nspawn update web -m 1g --cpus 2 --restart always
```

## Healthchecks

```shell
sudo nspawn start web --health-cmd "curl -fsS http://localhost/ || exit 1" --health-interval 10s --health-retries 3
```

Healthchecks are docker's. An image's `HEALTHCHECK` applies as it is, and
`--health-cmd` with `--health-interval`, `--health-timeout`,
`--health-retries`, `--health-start-period` and `--health-start-interval` on
`start`, `run`, `create` and `update` each replace their part of it
(`--health-interval 10s` alone keeps the image's test); `--no-healthcheck` turns
it off; timings given without a command on an image that has none are kept and
probe nothing. Durations are docker's (`10s`, `1m30s`, `500ms`), and so are the
defaults: 30 seconds between probes, 30 seconds for a probe, 3 failures in a
row before the machine is unhealthy, no start period, and 5 seconds between
probes during one.

The probe runs inside the machine as its user: a `--health-cmd` line through
the image's shell (`/bin/sh -c` unless its `SHELL` says otherwise), an image's
`CMD` form as it is (`exit 0` is healthy). It runs from a unit of its own,
`nspawn-health-NAME.service`, which requires the machine's and goes with it. The machine is `starting` until a probe succeeds or
the start period ends, `healthy` after a success and `unhealthy` after the
retries fail in a row; a success brings it back.

- `ps` shows the health next to the state: `running (healthy)`,
  `running (unhealthy)`, `running (health: starting)`.
- `inspect` shows `health` (the status), `health_failing_streak` and
  `health_log`, the last five probes as `END EXIT_CODE OUTPUT`, and
  `healthcheck` as it applies (durations in microseconds, 0 for docker's
  default):

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

## Dependencies

```shell
sudo nspawn network create shop
printf 'example' | sudo nspawn secret create pgpass
sudo nspawn run -d docker.io/library/postgres:17 --name db --network shop -v pgdata:/var/lib/postgresql/data \
  --secret pgpass -e POSTGRES_PASSWORD_FILE=/run/secrets/pgpass --health-cmd "pg_isready -U postgres" --health-interval 2s
sudo nspawn run -d docker.io/library/nginx:1.27 --name web --network shop -p 8080:80 --depends-on db:healthy
```

`--depends-on NAME[:CONDITION][:optional]` on `run`, `create` and `start` is
compose's `depends_on` for one machine: the other machine is started first,
and this one waits for what the condition asks of it.

| Condition | Waits until |
| --- | --- |
| `started` (the default) | the other machine's start went through. |
| `healthy` | its healthcheck says healthy; it needs one, and an unhealthy verdict fails the start. |
| `completed` | its program ended with 0, for a machine that prepares something and exits, such as a migration. It runs until one run of it succeeds: it runs first only when no run of it ended with 0 yet (a run of an earlier boot counts by the exit code the journal kept), not at every start or restart of the machines that depend on it. |

With `:optional` a failure of the other machine is a warning and this one
starts anyway. The flag is repeatable and remembered like the rest,
`--depends-on none` forgets them, and `inspect` lists them as `depends_on`.
The machines named must be nspawn's, a machine cannot depend on itself, and a
cycle is refused, `--network container:` counting as a dependency.

systemd does the work: the machine's unit wants the other one's and is ordered
after it (one that completes is only ordered after it, and the hook starts it
when it has to run), and its first hook, `nspawn await-dependencies`, waits for
the condition. So `machinectl start`, a start at boot and a restart policy follow
the same order as `nspawn start`, which says which machines it started or ran
first:

```text
$ sudo nspawn stop web db
stopped web
stopped db
$ sudo nspawn start web
started web
db started first: web depends on it
```

When a dependency fails, the start fails with its reason
(`web did not start: ...`). A start that waits for `healthy` or `completed`,
directly or through the machines its dependencies depend on, has no time
limit, since it lasts as long as the other machine takes; `nspawn stop` ends
it. A machine on another one's network (`--network container:NAME`) that also
depends on it has that machine started first. Stopping a machine leaves the ones
that depend on it running, as compose does, and `rm` refuses a machine others
depend on unless they are removed in the same command.

## The other flags of docker run

```shell
sudo nspawn start web --hostname web-1 -u nobody -w /tmp --cap-drop ALL --cap-add NET_BIND_SERVICE \
    --read-only --tmpfs /run:size=64m --tmpfs /tmp --shm-size 64m --device /dev/null:/dev/nullo \
    --dns 10.99.0.1 --dns-search example.test --add-host db:10.99.1.3 --add-host gw:host-gateway \
    --ulimit nofile=1024:4096 --oom-score-adj 500 --stop-signal SIGQUIT --stop-timeout 30 \
    --sysctl net.ipv4.icmp_echo_ignore_all=1
```

They work as in docker, are remembered like the rest and shown by
`inspect`. Each becomes a line of the machine's `.nspawn` settings file or of
its unit:

- `--hostname NAME`: the hostname inside, the machine's name by default. A
  booted machine gets it as its `/etc/hostname`, over the image's, since its
  systemd sets the hostname from that file.
- `-u USER[:GROUP]` and `-w DIR`: the user (a name or a uid, listed in the
  image's `passwd` or not, with a group of the image's `group` file or a gid
  after a colon, as docker's `--user` takes it; a group name the image lacks
  is refused) and the working directory the program runs with, instead of the
  image's. App images only; `exec` takes the same user unless its own `-u`
  says otherwise.
- `--cap-add`, `--cap-drop` and `--privileged`: capabilities added to or
  dropped from the default set (`NET_ADMIN` or `CAP_NET_ADMIN`; `ALL`). For an
  app on a bridge network, which runs without a user namespace, the default set
  is docker's (CHOWN, DAC_OVERRIDE, FOWNER, FSETID, KILL, MKNOD,
  NET_BIND_SERVICE, NET_RAW, SETFCAP, SETGID, SETPCAP, SETUID, SYS_CHROOT,
  AUDIT_WRITE) plus SYS_BOOT, so that a reboot from inside ends the machine; for
  a machine in a user namespace it is systemd-nspawn's. An interface given with
  `--interface` keeps `NET_ADMIN` on its own. `--cap-drop ALL --cap-add
  NET_BIND_SERVICE` keeps NET_BIND_SERVICE alone, as with docker, and
  `--privileged` keeps every one.
- `--read-only`: the root read-only. `--tmpfs PATH[:OPTIONS]`: an empty tmpfs
  at a path (`size=64m`, `mode=0700`; 1777 when given without options, as
  docker's), which is how a read-only machine still writes `/tmp` or
  `/var/cache`. `/run` is a tmpfs of every machine already, so a `--tmpfs` on or
  below it (`/var/run` in most images, docker's habit for a read-only nginx) is
  left out with a note. `--shm-size`: the size of `/dev/shm`.
- `--device HOST[:CONTAINER[:PERMISSIONS]]`: a device node of the host, bound
  into the machine and allowed to its cgroup (`r`, `w`, `m`; `rwm` by
  default), or a directory such as `/dev/dri`, whose nodes are allowed one by
  one. In a machine with private users the node keeps the host's
  ownership. A CDI name such as `nvidia.com/gpu=all` takes the devices of a
  spec instead; see [GPUs and CDI devices](#gpus-and-cdi-devices).
- `--dns` and `--dns-search`: the DNS servers and search domains the machine
  gets instead of the host's resolvers, in an app's generated `resolv.conf` and
  in a booted machine's `.network` file. `--add-host HOST:IP` (or `HOST=IP`, for
  an IPv6 address): lines for its `/etc/hosts`, `host-gateway` standing for the
  host's address on the machine's network.
- `--ulimit NAME=SOFT[:HARD]`: resource limits of the program (`nofile`,
  `nproc`, `core`, ...; `unlimited` is a value). `--oom-score-adj`: the
  machine's, -1000 to 1000.
- `--stop-signal` and `--stop-timeout`: what `stop` and `restart` use for the
  machine instead of the image's stop signal and the default 10 seconds; `-t` on
  `stop` still wins, and `-1` waits for as long as the program takes. `kill`
  reads the stop signal to decide whether the restart policy applies.
- `--timezone MODE`: how systemd-nspawn sets the machine's `/etc/localtime` at
  each start. Its default, `auto`, points it at the host's zone every time, so
  a zone set inside with `timedatectl` does not survive a restart; `off` leaves
  the machine's own, and `copy`, `bind`, `symlink` and `delete` are its other
  modes. An app also takes `-e TZ=`.
- `--log-driver DRIVER`: where the program's output goes. `local`, the
  default, sends it to journald's `nspawn` namespace, a journal of nspawn's
  own apart from the system's, so that a program that writes a lot never
  floods the host's logs; `logs` and an attached `run` read it, and
  `journalctl --namespace=nspawn` shows every machine's. It holds 1 GiB at
  most, shared by all machines, the oldest lines going first
  (`/usr/lib/systemd/journald@nspawn.conf`, which
  `/etc/systemd/journald@nspawn.conf` overrides). `journal` keeps the output
  in the system's journal, and `none` drops it: `logs` then refuses the
  machine, an attached `run` of an app still shows the output straight from
  the program, and an attached `run` of a booted machine, whose console goes
  nowhere, is refused: it runs with `-d`.
- `--init` and `--init=false`: the program under systemd-nspawn's stub init, which
  reaps orphans and turns a poweroff into SIGTERM, or as PID 1; see
  [App machines](#app-machines). App images only.
- `--sysctl KEY=VALUE`: `net.*` keys, set in the network namespace nspawn
  makes for an app machine on a bridge network, after
  `net.ipv4.ping_group_range=0 2147483647` and
  `net.ipv4.ip_unprivileged_port_start=0`, which that namespace gets as in a
  docker container. Nothing else is accepted, and a booted machine sets its
  own.
- `--interface IFACE`: a network interface of the host, moved into the
  machine while it runs and back on the host when it stops, a wifi adapter
  with its whole phy included; no docker counterpart. See [Physical
  interfaces](/docs/networking/#physical-interfaces).

A list takes `none` to forget it (`--cap-drop none`, `--tmpfs none`);
`--hostname`, `-u`, `-w`, `--stop-signal`, `--timezone` and `--log-driver` go
back to the default with an empty string (`--hostname ""`), `--shm-size` with
`0`, and `--privileged=false` and `--read-only=false` take those back. A path inside the
machine, the target of a volume or a secret, a `--tmpfs` or a `--device` path,
must be plain: a `.` or `..` component is refused, since it would land elsewhere
once mounted. A path the image
declares as a volume with nothing mounted over it gets a note at start: nspawn
has no anonymous volumes, so what is written there goes with the machine.

## GPUs and CDI devices

GPUs reach a machine through the Container Device Interface, as with docker
and podman. The vendor's tool writes a spec under `/etc/cdi` or `/var/run/cdi`
that lists the device nodes, libraries, variables and hooks each device needs
(`nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml` for NVIDIA,
`amd-ctk cdi generate` for AMD), and the machine names the devices:

```shell
sudo nspawn run -d --name app --gpus all IMAGE
sudo nspawn start app --device nvidia.com/gpu=0
```

`--device VENDOR/CLASS=NAME` takes a device by the spec's name (`=all`, `=0`, a
UUID), and docker's `--gpus all`, `--gpus 2` or `--gpus '"device=0,1"'` stands
for the devices of the NVIDIA spec (the AMD one when only that is there).
Compose's `gpus:`, the devices of `deploy.resources.reservations` and CDI names
in `devices:` do the same. The specs are read again at every start, so a driver
update that rewrites them takes effect at the next one: the device nodes are
bound into the machine and allowed in its cgroup, the libraries bound where the
spec says, the variables set after the machine's own, and the hooks
(`nvidia-cdi-hook update-ldcache`, `create-symlinks`) run just before the
machine starts, on its root.

Without a spec of the vendor, the start fails as docker's does:

```text
$ sudo nspawn run --rm --gpus all docker.io/library/busybox:1.37 -- true
error: could not select device driver "" with capabilities: [[gpu]]
```

The nodes are the host's, with the host's owner and mode. mstack machines take
no CDI devices. It is tested with specs written for the test suite, not with
real GPUs.

## Secrets

```shell
printf '%s' 'hunter2' | sudo nspawn secret create db-password
sudo nspawn start db --secret db-password -e POSTGRES_PASSWORD_FILE=/run/secrets/db-password
```

Secrets are docker's, without a swarm. `secret create NAME` reads the content
from standard input, or from `-f/--file`, and keeps it encrypted with
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
 db-password  7 B   9s ago   db
```

`secret inspect` prints what is known about them, never the content, and `secret rm`
removes the ones no machine takes; one a machine's record names is refused
until that machine is started with other secrets (or `--secret none`) or
removed. `mstack` machines take no secrets.

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
or not, as a JSON array, like `docker inspect`, for scripts.

`ps` also takes docker's scripting flags. `-q` prints the names alone (where
docker prints IDs), `--filter KEY=VALUE` keeps the machines that match (`name`
as a regular expression, `label`, `status`, `network`, `ancestor`, `health`,
`exited`, `volume`, `publish`, `expose`, `id`, `before`, `since`; the same key
twice matches either value, different keys all), and `--format` takes a Go
template over docker's fields (`.Names`, `.Image`, `.Command`, `.CreatedAt`,
`.RunningFor`, `.Ports`, `.State`, `.Status`, `.Labels`, `.Label "KEY"`,
`.Mounts`, `.Networks`) and nspawn's (`.Mode`, `.Address`, `.OS`, `.Pid`),
`table TEMPLATE` for aligned columns with headers, or `json` for an object per
line. `inspect -f TEMPLATE` prints a template over each object, a line each:

```text
$ sudo nspawn ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
NAMES     IMAGE          STATUS
web       nginx:alpine   Up 1 second
worker    busybox:1.37   Up Less than a second
$ sudo nspawn ps -q --filter label=tier=front
web
$ sudo nspawn inspect -f '{{.state}} {{index .labels "tier"}}' web worker
running front
running back
```

## exec and shell

```shell
sudo nspawn exec MACHINE [-u USER] [-e VAR[=VALUE]]... [-w DIR] [-T] [-t] [-i] [-d] COMMAND...
sudo nspawn shell MACHINE [-u USER]
```

`exec` runs one command inside a running machine of either kind and exits with
the command's status, so it works in scripts and pipelines. The program is looked
up on the machine's `PATH`, the image's environment and the `-e` variables of the
machine apply, and the working directory is the machine's. Neither D-Bus nor
anything else is needed inside. The flags are `docker exec`'s:

- Without `-u` the command runs as the machine's user, its `--user` or else its
  image's `USER`, as docker exec does, and as root on a booted machine.
  `-u USER[:GROUP]` takes names or numbers of the image's passwd and group
  files; with a group, that one is the only group.
- `-e` adds variables for this command, `-w` a working directory.
- A terminal is used when standard input and output are both one, so what goes
  through pipes is byte exact; `-T` refuses a terminal even from one and `-t`
  asks for one even without. `-i` is accepted for docker's sake.
- `-d` leaves the command running in the background and returns at once.

The command runs with the machine's capabilities and resource limits, like the
machine's own processes, with one exception: in an app that shares the host's
user namespace and is not `--privileged`, it goes without `CAP_SYS_BOOT`, which
the machine keeps only beside a seccomp filter against kexec that the command
does not carry. Right after a start, `exec` waits up to five seconds until
systemd-nspawn has finished confining the machine.

```text
$ sudo nspawn run -d --name worker -u 65534 docker.io/library/busybox:1.37 -- sleep 600
started worker
$ sudo nspawn exec worker -- id
uid=65534(nobody) gid=65534(nobody)
$ sudo nspawn exec -u root worker -- id
uid=0(root) gid=0(root)
```

`exec` and a healthcheck probe into a paused machine fail at once. `shell`
opens an interactive shell as `root` (or `-u USER`): machined's login session
for booted machines, `/bin/sh` in the machine's namespaces for apps.

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
  or not, never leads to the host. Links are copied as links (a source that
  ends in `/` or `/.` names the directory a link leads to); devices, sockets
  and fifos are left out, and so are the kernel's file systems mounted inside
  a running machine (`/proc`, `/sys` and the like).
- A tree more than 2048 directories deep is refused. A file that fails to read
  fails the copy: the file of that name on the other side stays as it was, and
  what was copied before it stays copied.

A stopped overlay or flat machine can be copied into and out of; a stopped
`mstack` machine cannot, since its tree only exists while it runs. Where
SELinux enforces, a host directory mounted with `-v` keeps its own label, which
the service may not be allowed to write to (docker needs `:z` for the same);
named volumes are nspawn's own and always work.

## logs

```shell
sudo nspawn logs MACHINE... [-f] [-n N] [--since WHEN] [--until WHEN] [-t] [--all] [--inside]
```

What the machine writes to its console goes, by default, to journald's
`nspawn` namespace under `systemd-nspawn@MACHINE.service`, apart from the
system's journal (see `--log-driver` above), and `logs` reads it with
`journalctl`, together with the system's journal, which holds systemd's lines
and the output of a machine with `--log-driver journal`. By default only the
machine's own output is shown, from its creation on, every run of it included;
a removed machine of the same name does not show:

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
pushes, kills, updates, pauses, auto-updates and removals, of networks, volumes
and secrets too. It
reads the journal, where systemd logs every start and end of a machine's unit
however it was started, and nspawn logs what it does, so `--since` reads past
events back. Filters take `name=`, `type=` (`machine`, `network`, `volume`,
`secret`), `event=` and `label=KEY` or `label=KEY=VALUE`: the same key given
twice matches either value, different keys must all match. `--json` prints one
object per event. What `events` printed while a network `backend` was made, `db`
ran on it with `run -d -l tier=data`, `run --rm --name job ... -- sh -c 'exit
3'` ran and ended, and `kill -s HUP db` ended `db`:

```text
2026-10-21T06:12:16.543884Z network create backend (created=1792563136, interface=nsbr-backend, internal=false, subnet=10.99.1.0/24)
2026-10-21T06:12:18.490159Z machine pull db (created=1792563138, image=docker.io/library/busybox:1.37, reference=docker.io/library/busybox:1.37, tier=data)
2026-10-21T06:12:18.843934Z machine start db (created=1792563138, image=docker.io/library/busybox:1.37, tier=data)
2026-10-21T06:12:20.792735Z machine pull busybox-1.37 (created=1792563140, image=docker.io/library/busybox:1.37, reference=docker.io/library/busybox:1.37)
2026-10-21T06:12:21.920339Z machine create job (created=1792563141, from=busybox-1.37, image=docker.io/library/busybox:1.37, reference=docker.io/library/busybox:1.37)
2026-10-21T06:12:22.569822Z machine start job (created=1792563141, image=docker.io/library/busybox:1.37)
2026-10-21T06:12:22.605119Z machine die job (code=exited, created=1792563141, exit_code=3, image=docker.io/library/busybox:1.37)
2026-10-21T06:12:22.641937Z machine fail job (created=1792563141, image=docker.io/library/busybox:1.37, result=exit-code)
2026-10-21T06:12:23.051001Z machine remove job (created=1792563141, image=docker.io/library/busybox:1.37)
2026-10-21T06:12:23.142907Z machine kill db (created=1792563138, image=docker.io/library/busybox:1.37, signal=1, tier=data)
2026-10-21T06:12:23.153501Z machine die db (code=exited, created=1792563138, exit_code=129, image=docker.io/library/busybox:1.37, tier=data)
```

Times are in UTC. A machine's `die` carries docker's exit code for that run:
128 plus the signal nspawn sent it (143 after a `stop`), or the status systemd
logged once the machine's record is gone (255 for an app killed by a signal).
nspawn's own events of a type carry the same attributes whatever the action, so
a `remove` says as much as a `create`: `image=` and `created=` (which machine of
the name it was) on a machine's, `subnet=`, `interface=`, `internal=` and
`created=` on a network's, `path=` on a volume's, `size=` on a secret's.
systemd's take `image=`, `created=` and the labels from the machine's record,
and lack them once it is removed.

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
release the network when the machine ends. With a restart policy, `--no-wait`
on an app also lets the stub init send the program SIGTERM and SIGHUP, since
nothing stays behind to stop the unit later. `-t -1` waits for as long as the
program takes, as docker's does. `-f` kills every process at once, like
`docker kill`. Stopping a machine that already ended is not an error, and a
paused machine is thawed first.

A machine with a restart policy stays stopped until it is started again: an
`unless-stopped` machine is also taken off the boot list until the next
`start`, while an `always` one still starts at the next boot.

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
machine as `paused`; `stop` thaws it first, and `kill` thaws it for a signal
that stops it.

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
the program of an app, or to the init of a booted machine, and, as with
docker, counts as a stop that keeps the restart policy from bringing the
machine back, unless the machine has a stop signal of its own (its image's
`STOPSIGNAL` or `--stop-signal`) and this is another one: then the policy
decides, should the signal end it. A booted machine's halt and poweroff
requests count as a stop; other signals to a booted machine leave it to the
policy. Right after a start, `kill` waits a few seconds at most for the program
to be running, so that the signal reaches it.

## wait and port

```text
$ sudo nspawn run --name job docker.io/library/busybox:1.37 -- sh -c 'exit 3'
$ sudo nspawn wait job
3
$ sudo nspawn port web
80/tcp -> 0.0.0.0:8080
80/tcp -> [::]:8080
```

`wait NAME...` waits for machines to stop and prints each one's exit code, and
`port NAME [PORT[/PROTO]]` the ports a running machine publishes, as docker's
do.

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

A machine that others depend on (`--depends-on`) or take their network from
(`--network container:NAME`) stays while they are there. Named in the same
command, they are removed first and the machine after them; one of them that
stays (running, without `-f`) keeps it too.

## The same machines on another host

`nspawn generate [NAME...]` prints the commands that make machines again, on
another host or on this one after a reinstall: a shell script with
`network create` for the networks they join, then `run -d` for each machine
with every flag it keeps, after the machines it depends on or takes its network
from, which come along when they are not named. Without names it covers every
machine nspawn has. For the two machines of [Dependencies](#dependencies):

```text
$ sudo nspawn generate web
# secret pgpass is encrypted for this host: nspawn secret create pgpass where this script runs, before it
nspawn network create shop --subnet 10.99.1.0/24
nspawn run -d --name db --pull always docker.io/library/postgres:17 \
  --network shop \
  --env POSTGRES_PASSWORD_FILE=/run/secrets/pgpass \
  --volume pgdata:/var/lib/postgresql/data \
  --health-cmd 'pg_isready -U postgres' \
  --health-interval 2s \
  --secret pgpass:/run/secrets/pgpass:0444:0:0
nspawn run -d --name web --pull always docker.io/library/nginx:1.27 \
  --network shop \
  --publish 8080:80 \
  --depends-on db:healthy
```

Each `run -d` pulls its machine on its own (`--pull always`; blobs already
there are not downloaded again), so that a machine never takes the network
kind, mode or backend of another one made from the same image. An image
without flags of its own is pulled again instead of run, unless another
machine takes its network, which needs it running. What a flag cannot carry is
said in comments at the top: a secret is encrypted for this host, so
`nspawn secret create` it there first; a host directory a machine mounts has
to exist there; an image built here has to be pushed first; a healthcheck in
exec form comes back as `--health-cmd`, which runs it through `/bin/sh`, so the
image needs one. The contents of named volumes and of a machine's writable layer
stay behind, and so do the addresses nspawn handed out: volumes are seeded again
from the image, and only addresses fixed with `--ip` come along.
