---
title: Command reference
linkTitle: Reference
weight: 8
description: >-
  Every command and option of nspawn 1.3.1.
---

`nspawn --help` and `nspawn COMMAND --help` print the same information. Errors
are printed as `error: ...` on standard error and the exit status is 1;
`exec` and an attached `run` exit with the status of the program they ran.

Every command but `daemon`, `completions` and the unit hooks is a call to the
[service](/docs/overview/#the-service) on the system bus, which asks polkit
whether the caller may take the action: the listings (`images ls`, `ps`,
`machines ls`, `inspect`, `top`, `stats`, `events`, `network ls`,
`network inspect`, `volume ls`, `secret ls`, `secret inspect`) ask for
`org.nspawn.inspect`; everything else, `search` and `hub` included, asks for
`org.nspawn.manage`. Both are for administrators by default, and root is never
asked.

## Global options

These are accepted by every command and can also come from the environment:

| Option | Environment | Meaning |
| --- | --- | --- |
| `--registry REGISTRY` | `NSPAWN_REGISTRY` | Registry (hub) for image references without a host part. |
| `--ca-cert FILE` | `NSPAWN_CA_CERT` | Extra CA certificate (PEM) to trust when talking to the registry. |
| `--config FILE` | `NSPAWN_CONFIG` | Configuration file; see [Configuration](/docs/configuration/). |
| `-h`, `--help` | | Help. |

`login` and `logout` take the registry as their argument, so there `--registry`
has to come before the subcommand: `nspawn --registry hub.example login -u me`.
`-V`, `--version` belongs to `nspawn` itself, not to the subcommands.

## hub

Query the hub (an OCI registry).

### hub ls

```text
nspawn hub ls [FILTER] [--no-tags]
```

Lists the repositories of the registry with their tags. `FILTER` keeps the
repositories whose name contains that text; `--no-tags` skips the tag query of
every repository, which is faster on big registries. `hub list` is an alias.

### hub tags

```text
nspawn hub tags REPOSITORY
```

Prints the tags of one repository, one per line.

## search

```text
nspawn search TERM [--source hub|dockerhub] [-n LIMIT]
```

Finds images on the hub and on Docker Hub, like `docker search`, and prints
every hit with its source and the reference `pull` takes.

| Option | Meaning |
| --- | --- |
| `TERM` | Text to look for in image names. |
| `--source hub\|dockerhub` | Only one source instead of both. |
| `-n`, `--limit LIMIT` | Results per source. Default: 25. |

## login

```text
nspawn login [REGISTRY] [-u USERNAME] [--password-stdin]
```

Checks credentials against a registry, like `docker login`, and keeps them in
`/etc/nspawn/auth.json` for `pull`, `push`, `search` and `hub`.

| Option | Meaning |
| --- | --- |
| `REGISTRY` | Registry host, for example `docker.io` or `hub.nspawn.org`. Default: the hub. |
| `-u`, `--username USERNAME` | User name; asked for on the terminal when missing. |
| `--password-stdin` | Read the password from standard input instead of the terminal. |

## logout

```text
nspawn logout [REGISTRY]
```

Forgets the credentials stored for a registry (the hub by default).

## pull

```text
nspawn pull REFERENCE [-n NAME] [--backend BACKEND] [--mode MODE] [-f] [--no-verify]
```

Downloads an image from the hub or another registry, checking its signature
first where the registry has a policy (the hub's is built in; see
[Signed images](/docs/images/#signed-images)), and makes it available to
systemd-machined. On a terminal a bar shows how far each blob got, with its
size, speed and time left; in a pipe or a log only the lines are written.

| Option | Meaning |
| --- | --- |
| `REFERENCE` | `[registry/]repository[:tag\|@digest]`, for example `fedora:44` or `docker.io/library/nginx`. |
| `-n`, `--name NAME` | Local image name. Default: derived from the reference, for example `fedora-44`. |
| `--backend auto\|overlay\|flat\|mstack` | How to assemble the image on this host. Default: `auto`, or the `backend` of the configuration file: `overlay`, or `flat` without overlayfs. `mstack` (systemd 261 or newer, managed user namespaces) is experimental. App images are assembled as `overlay` even when `mstack` is chosen. |
| `--mode auto\|boot\|app` | Whether the image boots an init system or runs a single program. Default: `auto`. |
| `-f`, `--force` | Replace an existing image with the same name. |
| `--no-verify` | Skip the signature check: the hub's images are signed and refused without a valid signature, and the configuration can ask the same of other registries; like docker's `--disable-content-trust`. |

## create

```text
nspawn create SOURCE NAME [--backend BACKEND] [--network NETWORK]... [--network-alias [NETWORK=]NAME]...
              [-p [IP:]HOST:CONTAINER[/udp]]... [--entrypoint PROGRAM] [-e VAR[=VALUE]]...
              [-v SOURCE:TARGET[:ro]]... [-l KEY=VALUE]... [--restart POLICY] [-m SIZE] [--memory-swap SIZE]
              [--cpus N] [--pids-limit N] [HEALTHCHECK OPTIONS] [OTHER OPTIONS] [--interface IFACE]... [--secret SECRET]...
              [-f] [--no-verify] [-- ARGUMENTS...]
```

Makes another machine from a local image, like `docker create`, without
touching the registry; a reference that is not local is pulled first, under
the image's own name, as `run` does. The layers are shared with the source.

| Option | Meaning |
| --- | --- |
| `SOURCE` | Local image to start from: its name, or the reference it was pulled from. A reference that is not local is pulled. |
| `NAME` | Name of the new machine. |
| `--backend BACKEND` | How to assemble it. Default: like the source. |
| `--network NETWORK` | Networks of the new machine, as for [start](#start). Default: the source's kind; a network made with `network create` is not inherited, as ports and labels are not. |
| `--network-alias [NETWORK=]NAME` | Other names of the machine on its networks, as for [start](#start). |
| `-p`, `--publish [IP:]HOST:CONTAINER[/udp]` | Ports to publish on the host, like `start -p`. Not inherited from the source. |
| `--entrypoint PROGRAM` | Replace the image's entrypoint; an empty string runs the arguments alone. App images only. |
| `-e`, `--env VAR[=VALUE]` | Environment for the program, `VAR=value` or `VAR` copied from the calling shell, like `docker -e`. App images only. |
| `-v`, `--volume SOURCE:TARGET[:ro]` | Mount a host directory or a named volume, like `docker -v`. |
| `-l`, `--label KEY=VALUE` | Label the machine, on top of the image's own labels, like `docker --label`. Not inherited from the source. |
| `--restart`, `-m`, `--memory-swap`, `--cpus`, `--pids-limit` | Restart policy and limits, as for [start](#start). Not inherited from the source. |
| the healthcheck options, the other options, `--interface`, `--secret` | As for [start](#start). Not inherited from the source. |
| `-f`, `--force` | Replace an existing machine with the same name. |
| `--no-verify` | Skip the signature check of an image that has to be pulled (a local source is not checked); like docker's `--disable-content-trust`. |
| `-- ARGUMENTS...` | App images: replace the image's cmd; they follow its entrypoint, as with docker. |

## build

```text
nspawn build [DIRECTORY] -t TAG [-n NAME] [-d DISTRIBUTION] [-r RELEASE]
             [--profile PROFILE]... [--backend BACKEND] [--mode MODE] [-f]
             [--keep-output] [-- MKOSI_ARGS...]
```

Builds an image with mkosi and makes it available locally, ready to push.
Needs mkosi.

| Option | Meaning |
| --- | --- |
| `DIRECTORY` | Directory with the mkosi configuration (`mkosi.conf`, `mkosi.conf.d`, ...). Default: `.`. |
| `-t`, `--tag TAG` | Reference for the result, for example `myapp:1` or `hub.example/team/app:2`. Required. |
| `-n`, `--name NAME` | Local image name. Default: derived from the tag. |
| `-d`, `--distribution DISTRIBUTION` | Distribution to build (`mkosi --distribution`). |
| `-r`, `--release RELEASE` | Release to build (`mkosi --release`). |
| `--profile PROFILE` | mkosi profile to enable; repeatable. |
| `--backend`, `--mode`, `-f` | As for `pull`. |
| `--keep-output` | Keep the mkosi output directory instead of deleting it after the import. |
| `-- MKOSI_ARGS...` | Extra arguments passed to mkosi verbatim. |

## push

```text
nspawn push IMAGE [--to REFERENCE]
```

Uploads a local image to the hub or another registry, with the credentials
stored for it. `IMAGE` is a local image name, or the reference it was pulled
from or built as. `--to` pushes it under a different reference than the one
recorded for the image. The destination needs a tag, not a digest. On a
terminal a bar shows how far each blob got, as with `pull`.

## images

Manage local images.

### images ls

```text
nspawn images ls [--json]
```

Lists the local images known to systemd-machined: name, type, and for the ones
nspawn installed the backend, origin (`pull`, `build` or `create`), source
reference, size and whether the image is read-only. `--json` prints the list as
the service returns it. `images list` is an alias.

### images rm

```text
nspawn images rm NAME...
```

Removes local images and the layers and blobs nobody uses any more. Refuses
the image of a running machine, or of one its restart policy is bringing back,
and a name nothing is behind. Named volumes are kept. A pulled image is a machine too, so this is the same as
[rm](#rm) without `--force`.

## rm

```text
nspawn rm [-f] NAME...
```

Removes machines, like `docker rm`: the record, the tree, the unit files, the
boot link a restart policy made, and the layers and blobs nobody else uses.
Every name is tried; one that cannot be removed, or that nothing is behind
(`no machine or image named NAME`), is reported at the end. Named volumes are
kept, and each one kept is mentioned.

| Option | Meaning |
| --- | --- |
| `-f`, `--force` | Stop a running (or restarting) machine first, with SIGKILL, instead of refusing it. |

## ps, machines ls

```text
nspawn ps [-a] [--json]
nspawn machines ls [-a] [--json]
```

Lists the running machines, like `docker ps`: name, image, mode, command,
state, uptime, leader PID, network and OS. A machine whose restart policy is
bringing it back shows as `restarting`, even without `-a`. `-a`, `--all` also
lists the nspawn machines that are not running: `stopped`, or `starting` and
`closing` while their unit comes up or goes down. `--json` prints what the service returns for
each machine, its whole record included. `machines list` is an alias of
`machines ls`.

## inspect

```text
nspawn inspect NAME...
```

Prints everything nspawn knows about machines or images, running or not, as a
JSON array with one object per name, like `docker inspect`: the record (image
reference, digest, backend, mode, networks, addresses, aliases, ports, volumes,
environment, command, labels, restart policy, limits, healthcheck, secrets,
the other flags, and who signed the image and when, as the pull verified it:
`signed_by`, `signed_at`), for a running machine its state, start time, leader
PID, OS and health, and for a stopped one the exit code of its last run. The keys are
those of the
[D-Bus interface](https://github.com/nspawn/nspawn/blob/master/docs/DBUS.md).

## start

```text
nspawn start NAME [--network NETWORK]... [--network-alias [NETWORK=]NAME]... [-p [IP:]HOST:CONTAINER[/udp]]...
             [--entrypoint PROGRAM] [-e VAR[=VALUE]]... [-v SOURCE:TARGET[:ro]]... [-l KEY=VALUE]...
             [--restart POLICY] [-m SIZE] [--memory-swap SIZE] [--cpus N] [--pids-limit N]
             [--health-cmd COMMAND] [--health-interval D] [--health-timeout D] [--health-retries N]
             [--health-start-period D] [--health-start-interval D] [--no-healthcheck]
             [--hostname NAME] [-u USER[:GROUP]] [-w DIR] [--cap-add CAP]... [--cap-drop CAP]... [--privileged]
             [--read-only] [--tmpfs PATH[:OPTIONS]]... [--shm-size SIZE]
             [--device HOST[:CONTAINER[:PERMISSIONS]]]... [--dns ADDRESS]... [--dns-search DOMAIN]...
             [--add-host HOST:IP]... [--ulimit NAME=SOFT[:HARD]]... [--oom-score-adj N]
             [--stop-signal SIGNAL] [--stop-timeout SECONDS] [--timezone MODE] [--init] [--sysctl KEY=VALUE]...
             [--interface IFACE]... [--secret NAME[:TARGET[:MODE[:UID:GID]]]]... [--image-command] [--no-wait]
             [-- ARGUMENTS...]
```

Boots an image as a machine. Every option is remembered for the next start.

| Option | Meaning |
| --- | --- |
| `--network NETWORK` | Network of the machine: `bridge`, the default network (the default); the name of a network made with [network create](#network-create); `veth`, a veth pair configured by systemd-networkd on the host (booted images only); `host`, the host's own network; `none`, no interface but `lo`; or `container:NAME`, the network namespace of that running machine, like `docker run --network container:NAME` (app images only; see [container:NAME](/docs/networking/#containername)). Repeatable for several bridge networks, the first one primary: its address is where published ports lead and its gateway the default route, unless it is internal, in which case the first network that is not has the route. `veth`, `host`, `none` and `container:NAME` go alone. |
| `--network-alias [NETWORK=]NAME` | Another name for the machine on its primary network, or on `NETWORK`, like `docker --network-alias`: every member of that network resolves it. Repeatable; `none` forgets them. |
| `-p`, `--publish [IP:]HOST:CONTAINER[/udp]` | Publish a port on the host, like `docker -p`: on every address of the host, or on `IP` alone (`127.0.0.1:8080:80`). `8000-8010:8000-8010` publishes a range, one mapping per port. Repeatable; `none` forgets them all. |
| `--entrypoint PROGRAM` | Replace the image's entrypoint; an empty string runs the arguments alone. App images only. |
| `-e`, `--env VAR[=VALUE]` | Environment for the program, `VAR=value` or `VAR` copied from the calling shell. Repeatable; `none` forgets them. App images only. |
| `-v`, `--volume SOURCE:TARGET[:ro]` | Mount a host directory or a named volume, made on first use with what the image has at `TARGET`, as docker seeds one. Repeatable; `none` forgets them. |
| `-l`, `--label KEY=VALUE` | Label the machine, on top of the image's own labels. Repeatable; `none` forgets them. |
| `--restart no\|on-failure\|always\|unless-stopped` | Restart policy, like `docker --restart`. `always` and `unless-stopped` also start the machine at boot; `nspawn stop` takes an `unless-stopped` machine off the boot list until the next `start`. Applied at the next start; [update](#update) changes it at once. |
| `-m`, `--memory SIZE` | Memory limit of the whole machine, like `docker -m`: `512m`, `2g` (at least `4m`), and as much swap again unless `--memory-swap` says otherwise; `0` removes it. Applied at the next start; [update](#update) changes it at once. |
| `--memory-swap SIZE` | Memory and swap together, like `docker --memory-swap`: equal to `--memory` for no swap, larger for the difference, `-1` for swap without a bound; `0` goes back to as much swap again as memory. Needs `--memory`. Applied at the next start; [update](#update) changes it at once. |
| `--cpus N` | CPU limit of the whole machine, like `docker --cpus`: `0.5`, `2`; `0` removes it. Applied at the next start; [update](#update) changes it at once. |
| `--pids-limit N` | Most processes and threads the machine may have (at least 16 for a booted machine); `0` removes the limit. Applied at the next start; [update](#update) changes it at once. |
| `--health-cmd COMMAND` | Command that says whether the machine is healthy, run inside it through `/bin/sh -c` at every interval, like `docker --health-cmd`: exit 0 is healthy. Replaces the image's `HEALTHCHECK`. [update](#update) changes it at once. |
| `--health-interval D` | Time between probes: `10s`, `1m30s`, `500ms`. Default: `30s`. |
| `--health-timeout D` | Time a probe may take before it counts as failed. Default: `30s`. |
| `--health-retries N` | Consecutive failed probes that make the machine unhealthy. Default: 3. |
| `--health-start-period D` | Time after the start during which failed probes do not count. Default: `0s`. |
| `--health-start-interval D` | Time between probes during the start period. Default: `5s`. |
| `--no-healthcheck` | No probes, whatever the image says. |
| `--hostname NAME` | Hostname inside the machine. Default: its name. A booted machine gets it as its `/etc/hostname`. |
| `-u`, `--user USER[:GROUP]` | User the program runs as, a name or a uid (listed in the image's `passwd` or not), instead of the image's, with a group after a colon as docker takes it: a name of the image's `group` file or a number, which becomes the primary and only group of the program; a name the image lacks is refused. nspawn resolves both from the image's `passwd` and `group` files through a stand-in for getent, as docker does. App images only. |
| `-w`, `--workdir DIR` | Working directory of the program, instead of the image's. App images only. |
| `--cap-add CAP` | Capability to keep on top of the default set (docker's and SYS_BOOT for an app on a bridge network, systemd-nspawn's for a machine in a user namespace): `NET_ADMIN`, `CAP_NET_ADMIN`, `ALL`. Repeatable; `none` forgets them. |
| `--cap-drop CAP` | Capability to drop from the default set. `--cap-drop ALL --cap-add X` keeps `X`, as with docker. Repeatable; `none` forgets them. |
| `--privileged` | Every capability, like `docker --privileged`; `--privileged=false` takes it back. |
| `--read-only` | Mount the machine's root read-only; `--read-only=false` takes it back. |
| `--tmpfs PATH[:OPTIONS]` | An empty tmpfs at a path inside (`/tmp:size=64m,mode=1777`). One that lands on `/run`, a tmpfs of every machine already, is left out with a note. Repeatable; `none` forgets them. |
| `--shm-size SIZE` | Size of `/dev/shm`: `64m`, `1g`; `0` for the default. |
| `--device HOST[:CONTAINER[:PERMISSIONS]]` | A device node of the host for the machine, like `docker --device` (`/dev/ttyUSB0:/dev/ttyUSB0:rw`), or a directory whose nodes are allowed one by one (`/dev/dri`). Repeatable; `none` forgets them. |
| `--dns ADDRESS` | DNS server for the machine, instead of the host's. Repeatable; `none` forgets them. |
| `--dns-search DOMAIN` | DNS search domain. Repeatable; `none` forgets them. |
| `--add-host HOST:IP` | A line for the machine's `/etc/hosts`, `HOST:IP` or `HOST=IP` (the second for an IPv6 address); `host-gateway` is the host's address on the machine's network. Repeatable; `none` forgets them. |
| `--ulimit NAME=SOFT[:HARD]` | A resource limit of the program, like `docker --ulimit` (`nofile=1024:4096`, `core=unlimited`). Repeatable; `none` forgets them. |
| `--oom-score-adj N` | OOM score adjustment of the machine, -1000 to 1000. |
| `--stop-signal SIGNAL` | Signal `stop` sends the program, instead of the image's (`SIGTERM`). |
| `--stop-timeout SECONDS` | Seconds `stop` waits after the signal before SIGKILL, unless `-t` says otherwise. Default: 10. |
| `--timezone MODE` | How systemd-nspawn sets the machine's `/etc/localtime` at each start, its `Timezone=`: `auto` (the default, the host's zone), `off` (left alone, so a zone set inside stays), `copy`, `bind`, `symlink` or `delete`. `auto` forgets the setting. |
| `--init` | Accepted for docker's sake: nspawn's stub init reaps orphans anyway. App images only. |
| `--sysctl KEY=VALUE` | A `net.*` sysctl for an app machine's network namespace. Repeatable; `none` forgets them. |
| `--interface IFACE` | A network interface of the host, moved into the machine while it runs and given back when it stops: an ethernet one, or a wifi adapter with its whole phy (`iw` on the host for an app on the bridge, systemd 256 for a booted machine); the name is kept inside. Not with `--network host` or `container:NAME`; one machine at a time. See [Physical interfaces](/docs/networking/#physical-interfaces). Repeatable; `none` forgets them. |
| `--secret NAME[:TARGET[:MODE[:UID:GID]]]` | A secret made with [secret create](#secret-create) as a read-only file inside the machine, like docker's `--secret`: `NAME` alone is `/run/secrets/NAME` with mode 0444, root's. Repeatable; `none` forgets them. Not on `mstack` machines. |
| `--image-command` | Forget the remembered entrypoint and arguments and run the image's own again. |
| `--no-wait` | Do not wait for a booted machine's init to be up before returning. Its registration is still awaited, so that ports and firewall rules can be applied. |
| `-- ARGUMENTS...` | App images: replace the image's cmd; they follow its entrypoint, as with docker. |

A path inside the machine, the target of `-v` or `--secret`, a `--tmpfs` or a
`--device` path, must be plain: a `.` or `..` component is refused.

## run

```text
nspawn run [-d] [--rm] [-i] [-t] [-n NAME] [--pull missing|always|never]
           [--backend BACKEND] [--mode MODE] [-f] [--no-verify] [OPTIONS OF start] [--no-wait]
           REFERENCE [COMMAND [ARGUMENT...]]
```

Makes a machine from an image and starts it, like `docker run`: `pull` (or
`create` from a local image with the same reference) followed by `start`, whose
options are remembered as after `start`. What `pull` or `create` report goes to
standard error, so that standard output carries the program's output alone.

Without `-d`, `run` stays attached, as `docker run` does. The machine's output
follows until the machine ends, a line at a time, stdout and stderr together:
it is read from the journal, so `nspawn logs NAME` shows it later too, and the
machine goes on should `run` be interrupted. `run` exits with the program's
exit code, or 128 plus the signal it died of (130 after Ctrl-C, 137 after
`kill`). Ctrl-C, SIGTERM, SIGHUP and SIGQUIT are passed on to the program; a
third Ctrl-C within a second leaves the machine running and returns. A booted
image shows its console until it powers off, and Ctrl-C powers it off.

| Option | Meaning |
| --- | --- |
| `REFERENCE` | `[registry/]repository[:tag\|@digest]`, for example `nginx:1.27`. |
| `COMMAND [ARGUMENT...]` | App images: replace the image's cmd and follow its entrypoint, as with docker; everything after the reference that is not an option of `run`, or everything after `--`. |
| `-d`, `--detach` | Start the machine in the background and return, like `docker run -d`; `nspawn logs -f NAME` follows its output. |
| `--rm` | Remove the machine once it ends, with or without `-d`; named volumes stay. An image the run had to pull is kept under the image's local name when that name is free, as docker keeps images, and without `--name` the machine gets a name of its own (`alpine-3-1f0c9a2e`). Refused with a restart policy. A run that fails to start leaves nothing behind. |
| `-i`, `--interactive` | App images: give the program this standard input, like `docker run -i`. |
| `-t`, `--tty` | App images: give the program a terminal, like `docker run -t`; Ctrl-C and resizes reach it through the terminal. Closing the terminal stops the machine. With `-i` on a booted image: wait for it to boot, open a root shell, and power it off when the shell ends, with the shell's exit code. Not with `-d`. |
| `-n`, `--name NAME` | Name of the machine. Default: derived from the reference, for example `nginx-1.27`. A name that is taken is refused, with a pointer to `start`. |
| `--pull missing\|always\|never` | When to ask the registry. `missing`, the default: a local image with the same reference is made into the machine, as `create` does, and the registry is asked only when there is none. `always`: every time, for the image the tag names now. `never`: a local image or nothing. |
| `--backend auto\|overlay\|flat\|mstack` | How to assemble the machine, as for `pull`. |
| `--mode auto\|boot\|app` | As for `pull`; a mode other than `auto` always pulls. |
| `-f`, `--force` | Make the machine anew when one of that name exists; it must be stopped. |
| `--no-verify` | Skip the signature check of the image, as for `pull`. |
| the options of `start` | `--network`, `--network-alias`, `-p`, `--entrypoint`, `-e`, `-v`, `-l`, `--restart`, `-m`, `--cpus`, `--pids-limit`, the healthcheck options, the other options, `--interface`, `--secret` and `--no-wait` (with `-d` only), as for [start](#start). Options may come before or after the reference, as long as they come before the command. |

## stop

```text
nspawn stop NAME... [-f] [-t TIMEOUT] [--no-wait]
```

Powers off running machines, one after the other: the machine's stop signal
(`--stop-signal`, else the image's) to the program of an app, a poweroff
request to a booted machine. Stopping a machine that already ended only cleans
up after it, and a paused one is thawed first. A machine with a restart policy
stays stopped, and one that was waiting to be restarted is stopped too. An
`unless-stopped` machine is also taken off the boot list until the next
`start`; an `always` one stays enabled and starts again at the next boot (`rm`
takes that away). Every name is tried; one that could not be stopped is
reported at the end.

| Option | Meaning |
| --- | --- |
| `-f`, `--force` | Kill every process at once instead of asking the machine to stop. |
| `-t`, `--timeout TIMEOUT` | App images: seconds to wait after the stop signal before killing the machine. Default: the machine's `--stop-timeout`, else 10. |
| `--no-wait` | Return right after the stop request, without waiting for the machine to be gone and without the kill after the timeout. |

## restart

```text
nspawn restart NAME... [-t TIMEOUT]
```

Stops and starts machines, like `docker restart`: a [stop](#stop) followed by
a [start](#start) with everything the machine remembers, and prints each name
once it runs again. A machine that is not running is started. Every name is
tried; one that could not be restarted is reported at the end.

| Option | Meaning |
| --- | --- |
| `-t`, `--timeout TIMEOUT` | As for `stop`. |

## kill

```text
nspawn kill [-s SIGNAL] NAME...
```

Sends a signal to running machines, like `docker kill`, and prints each name
once it is sent. SIGKILL, the default, stops the machine for good, as
`stop --force` does. Any other signal goes to the program of an app or the
init of a booted machine, and the machine lives on unless the signal ends it,
in which case its restart policy applies; the machine's own stop signal (an
app's, or SIGRTMIN+3 and SIGRTMIN+4 for a booted machine's init) ends it for
good, as docker does.

| Option | Meaning |
| --- | --- |
| `-s`, `--signal SIGNAL` | A name (`KILL`, `SIGHUP`, `RTMIN+3`) or a number. Default: `KILL`. |

## pause, unpause

```text
nspawn pause NAME...
nspawn unpause NAME...
```

`pause` freezes every process of running machines through the cgroup freezer
of their units, like `docker pause`, and `unpause` thaws them; each name is
printed once done. `ps` and `inspect` show a frozen machine as `paused`, and
`stop` and `kill` thaw it first.

## update

```text
nspawn update NAME... [--restart POLICY] [-m SIZE] [--memory-swap SIZE] [--cpus N] [--pids-limit N]
              [--health-cmd COMMAND] [--health-interval D] [--health-timeout D] [--health-retries N]
              [--health-start-period D] [--health-start-interval D] [--no-healthcheck]
```

Changes the restart policy, the limits and the healthcheck of machines, like
`docker update`, and prints each name once changed. A running machine gets the
new limits and healthcheck at once (its probes start afresh) and the policy for
its next ending; a stopped one at its next start. The options are those of
[start](#start); at least one is needed.

## exec

```text
nspawn exec MACHINE [-u USER] [-e VAR[=VALUE]]... [-w DIR] [-T] [-t] [-i] [-d] COMMAND...
```

Runs a command inside a running machine of either kind, attached to the
terminal when standard input and output are one, in the machine's namespaces,
with the image's environment and the machine's `-e` variables. The program is found on the machine's `PATH` and
runs with the machine's capabilities and resource limits, like its own
processes, except `CAP_SYS_BOOT` in an app that shares the host's user namespace
(unless `--privileged`), since the command does not carry the seccomp filter that
keeps kexec out of the machine; right after a start it waits, a few seconds at most, until
systemd-nspawn has finished confining the machine. Exits with the command's
status.

| Option | Meaning |
| --- | --- |
| `-u`, `--user USER[:GROUP]` | User inside the machine, a name or a number of its passwd file, with a group of its group file after a colon (then the only group; otherwise the user's supplementary groups come along) and the home of the passwd entry. Default: `root`. |
| `-e`, `--env VAR[=VALUE]` | A variable for the command, `VAR=value` or `VAR` copied from the calling shell, like `docker exec -e`. Repeatable. |
| `-w`, `--workdir DIR` | Working directory of the command, instead of the machine's. |
| `-T`, `--no-tty` | No terminal, even from one: pipes, as in a script. Without `-t` or `-T`, a terminal only when standard input and output are one, so redirected output is byte-exact. |
| `-t`, `--tty` | A terminal for the command, even without one here. |
| `-i`, `--interactive` | Accepted for docker's sake: the command's input is always this one. |
| `-d`, `--detach` | Leave the command running in the background and return at once. |
| `COMMAND...` | Command and arguments. |

## shell

```text
nspawn shell MACHINE [-u USER]
```

Opens an interactive shell inside a running machine as `USER` (default
`root`): machined's login session for booted machines, `/bin/sh` in the
machine's namespaces for app machines.

## top

```text
nspawn top MACHINE
```

Lists the processes of a running machine, like `docker top`: `PID` as the
host sees it, `USER` as the machine sees it, `TIME` of CPU and `COMMAND`,
read from the machine's cgroup and PID namespace.

## cp

```text
nspawn cp MACHINE:PATH DESTINATION
nspawn cp SOURCE MACHINE:PATH
```

Copies files and directories between the host and a machine, like
`docker cp`. The machine may be running, or stopped if it is an overlay or flat
machine; a stopped mstack machine has no tree on the host until it runs.

- An existing directory as the destination receives the source under its own
  name; anything else is the name of the copy, whose parent must exist. A
  destination ending in `/` must be a directory.
- `DIR/.` as the source copies the contents of DIR instead of DIR itself.
- What goes into a machine belongs to its root, whatever user namespace the
  machine runs in; what comes out belongs to the user who ran `cp`. Modes and
  modification times are kept.
- Paths inside the machine are resolved inside it: a link there, absolute or
  not, never leads to the host. Links are copied as links; devices, sockets and
  fifos are left out, and so are the kernel's file systems mounted inside a
  running machine (`/proc`, `/sys` and the like).
- A relative path after `MACHINE:` starts at the machine's root. A local path
  with a colon is written `./a:b`.

## logs

```text
nspawn logs MACHINE... [-f] [-n N] [--since WHEN] [--until WHEN] [-t] [--all] [--inside]
```

Shows what machines printed, like `docker logs`. With several machines every
line carries its machine's name (`web | ...`), the way docker compose shows
them.

| Option | Meaning |
| --- | --- |
| `-f`, `--follow` | Keep printing new output; starts from the last 10 lines unless `--lines` says otherwise. |
| `-n`, `--lines N` | Only the last N lines. |
| `--since WHEN` | Only output newer than this, in `journalctl --since` syntax, for example `"10 min ago"` or `-1h`. |
| `--until WHEN` | Only output older than this, in `journalctl --until` syntax; nothing is followed then. |
| `-t`, `--timestamps` | Prefix every line with its timestamp. |
| `--all` | Also show what systemd says about the machine's service: start, stop, failures. |
| `--inside` | Booted machines only: read the machine's own journal instead of its console output. |

## stats

```text
nspawn stats [NAME...] [--no-stream] [--json]
```

Shows what running machines use, like `docker stats`: CPU (100% is one CPU
busy), memory in use against the limit (the host's memory without one),
network and disk traffic, and processes, read from the cgroup of each machine's
unit, which holds the whole machine. Without names it shows every running
machine. The table is drawn again every second on a terminal.

| Option | Meaning |
| --- | --- |
| `--no-stream` | Print one table, from two readings a second apart, and return. |
| `--json` | One JSON object per machine and reading instead of the table. |

## events

```text
nspawn events [--since WHEN] [--until WHEN] [-f KEY=VALUE]... [--json]
```

Reports what happens to machines, networks, volumes and secrets, like
`docker events`: for machines `start`, `die` (with its exit code), `stop`,
`restart`, `oom` and `fail`, which systemd logs for every machine however it
was started, `health_status` (with the new status) and what nspawn does,
`pull`, `build`, `create`, `push`, `kill`, `update` and `remove`; for
networks, volumes and secrets `create` and `remove`. It reads the journal, so
past events can be read back.

| Option | Meaning |
| --- | --- |
| `--since WHEN` | Events since this time, in `journalctl --since` syntax (`"2026-09-24 10:00"`, `-1h`, `today`). Without it, only new ones. |
| `--until WHEN` | Stop at this time instead of waiting for new events; needs `--since`. |
| `-f`, `--filter KEY=VALUE` | Only matching events: `name=NAME`, `type=machine\|network\|volume\|secret`, `event=ACTION`, `label=KEY` or `label=KEY=VALUE`. The same key given twice matches either value, different keys must all match. |
| `--json` | One JSON object per event: `time`, `time_usec`, `type`, `action`, `name`, `attributes`, `labels`. |

## network

The default network (`bridge`) and the ones made with `network create`.

### network up

```text
nspawn network up
```

Brings up every network's bridge with its NAT rules and firewall exceptions,
and brings the published ports in line with the machines that run. `start`
does it for its machine's network too; this is useful at boot and for
troubleshooting.

### network ls

```text
nspawn network ls [--json]
```

Lists the networks, the default one first: name, bridge interface, subnet,
whether it is internal, and the machines whose records name it. `--json`
prints them as the service returns them. `network list` is an alias.

### network create

```text
nspawn network create NAME [--subnet CIDR] [--internal] [-l KEY=VALUE]...
```

Makes a network of its own, like `docker network create`: a bridge `nsbr-NAME`
(hashed when the name is long) with its NAT and firewall rules, brought up at
once. Machines of one network reach each other by name, and nothing of another
network, the default one included, reaches them; ports they publish are
reachable from everywhere through the host, as from the LAN.

| Option | Meaning |
| --- | --- |
| `NAME` | Letters, digits, `_` and `-`; not `bridge`, `host`, `veth`, `none` or `default`. |
| `--subnet CIDR` | The network's IPv4 subnet. Default: the next free /24 of `network_pool` (see [Configuration](/docs/configuration/)), never one the host already routes. |
| `--internal` | No way out: its machines reach each other and the host, nothing beyond, and cannot publish ports. |
| `-l`, `--label KEY=VALUE` | Label the network, like `docker network create --label`. Repeatable. |

### network inspect

```text
nspawn network inspect NAME...
```

Prints networks as a JSON array, like `docker network inspect`: name,
interface, subnet, gateway, whether it is internal, its labels, and its
machines with their addresses, aliases, ports and whether they run. `bridge`
is the default network.

### network rm

```text
nspawn network rm NAME...
```

Removes networks no machine uses, with their bridges and rules. A network a
machine's record names is refused, with the machines that use it; the default
network cannot be removed. `network remove` is an alias.

### network prune

```text
nspawn network prune [-f]
```

Removes every network no machine uses, after asking on standard input unless
`-f` is given.

## volume

Named volumes, the directories `-v NAME:/path` makes under
`/var/lib/nspawn/volumes`. Removing a machine keeps them.

### volume ls

```text
nspawn volume ls [--json]
```

Lists the named volumes with the machines whose records mount them, when each
was made and its path. `--json` prints the list as the service returns it.
`volume list` is an alias.

### volume create

```text
nspawn volume create NAME
```

Makes a volume ahead of its first use (`start` makes it otherwise): a
directory owned by root, mode 0755. One that exists already is fine. Names have
letters, digits, `_`, `.` and `-`, not starting with a dot.

### volume rm

```text
nspawn volume rm NAME...
```

Removes volumes no machine uses. A volume a machine still names is refused
until that machine is started with other volumes (or `-v none`) or removed.

### volume prune

```text
nspawn volume prune [-f]
```

Removes every volume no machine uses once a yes comes on standard input, as
docker does: from a script, whose input ends without one, nothing is removed.
`-f` removes them without asking.

## secret

Secrets, like docker's without a swarm: kept encrypted on the host with
`systemd-creds`, handed to machines as files by `--secret` on `start`, `run`
and `create`.

### secret ls

```text
nspawn secret ls [--json]
```

Lists the secrets: name, when it was made, the size of its plaintext, its
labels and the machines that take it; never the content. `--json` prints the
list as the service returns it. `secret list` is an alias.

### secret create

```text
nspawn secret create NAME [--file FILE] [-l KEY=VALUE]...
```

Keeps a secret read from standard input, or from `--file`, encrypted for this
host: bound to its TPM2 where there is one, to its credential key otherwise,
under `/var/lib/nspawn/secrets`. A name that exists already is refused.

| Option | Meaning |
| --- | --- |
| `NAME` | Letters, digits, `_`, `.` and `-`. |
| `--file FILE` | Read the content from this file instead of standard input. |
| `-l`, `--label KEY=VALUE` | Label the secret, like `docker secret create --label`. Repeatable. |

### secret inspect

```text
nspawn secret inspect NAME...
```

Prints what nspawn keeps about secrets as a JSON array: name, creation time,
size, labels and the machines that take them; never the content.

### secret rm

```text
nspawn secret rm NAME...
```

Removes secrets no machine takes. One a machine's record names is refused,
with the machines that take it, until they are started with other secrets (or
`--secret none`) or removed. Every name is tried; one that cannot be removed is
reported at the end. `secret remove` is an alias.

## daemon

```text
nspawn daemon [--install] [--idle-exit SECONDS]
```

Serves `org.nspawn` on the system bus. The bus starts it on demand, so this is
not a command to type; `--install` is.

| Option | Meaning |
| --- | --- |
| `--install` | Write the bus policy, the polkit actions, the activation file and the unit that let the bus start this binary on demand, then return. A package does the same. |
| `--idle-exit SECONDS` | Exit after this long without a call or a running job. Default: 60; `0` keeps serving. |

## completions

```text
nspawn completions bash|elvish|fish|powershell|zsh
```

Writes the completions for that shell on standard output; they come from the
same definition the command line itself is built from. The packages install
them, so this is for a binary you built yourself:

```shell
nspawn completions bash > ~/.local/share/bash-completion/completions/nspawn
```

`man nspawn` is the same reference as this page, generated the same way.

### Unit hooks

`nspawn network prepare NAME`, `nspawn network publish NAME` and
`nspawn network release NAME` are what the drop-in of
`systemd-nspawn@NAME.service` runs as `ExecStartPre`, `ExecStartPost` and
`ExecStopPost`, and `nspawn health-run NAME` is what
`nspawn-health-NAME.service` runs to probe a machine's healthcheck. They are
not meant to be typed and are hidden from `--help`.
