---
title: Command reference
linkTitle: Reference
weight: 10
description: >-
  Every command and option of nspawn 2.3.2.
---

`nspawn --help` and `nspawn COMMAND --help` list the options; this page
explains them in full. Errors are printed as `error: ...` on standard error and
the exit status is 1 (2 for a command line clap refuses); `exec` and an attached
`run` exit with the status of the program they ran, and `nspawn compose` prints
its errors as docker compose does.

Every command but `daemon`, `completions` and the unit hooks is a call to the
[service](/docs/overview/#the-service) on the system bus, which asks polkit
whether the caller may take the action: the listings (`images ls`, `ps`,
`machines ls`, `inspect`, `generate`, `top`, `stats`, `events`, `wait`,
`port`, `system df`, `builder du`, `network ls`, `network inspect`,
`volume ls`, `secret ls`, `secret inspect`) ask for
`org.nspawn.inspect`; everything else, `search` and `hub` included, asks for
`org.nspawn.manage`. Both are for administrators by default, and root is never
asked.

## Global options

These are accepted by every command and can also come from the environment;
`nspawn compose` ignores them, with a warning, as its pulls take the service's
configuration:

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

Finds images on the hub and on Docker Hub and prints
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

Checks credentials against a registry (`GET /v2/`, then basic authentication
or a token from the realm the registry names) and keeps them in
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
| `--no-verify` | Skip the signature check: the hub's images are signed and refused without a valid signature, and the configuration can ask the same of other registries. |

## create

```text
nspawn create SOURCE NAME [--backend BACKEND] [--network NETWORK]... [--network-alias [NETWORK=]NAME]...
              [-p [IP:]HOST:CONTAINER[/udp]]... [--entrypoint PROGRAM] [-e VAR[=VALUE]]...
              [-v SOURCE:TARGET[:ro]]... [-l KEY=VALUE]... [--restart POLICY] [-m SIZE] [--memory-swap SIZE]
              [--cpus N] [--pids-limit N] [HEALTHCHECK OPTIONS] [OTHER OPTIONS] [--interface IFACE]... [--secret SECRET]...
              [--depends-on NAME[:CONDITION][:optional]]... [--env-file FILE]... [--label-file FILE]...
              [--mount type=TYPE,source=SRC,target=DST]... [--ip [NETWORK=]IP]... [--gpus REQUEST]... [-f] [--no-verify] [-- ARGUMENTS...]
```

Makes another machine from a local image without
touching the registry; a reference that is not local is pulled first, under
the image's own name, as `run` does. The layers are shared with the source.

| Option | Meaning |
| --- | --- |
| `SOURCE` | A local image name, used as it is. Otherwise a reference: the image of that reference that never ran, the last one pulled when there are several; a name without a registry is looked for under the configured one, then as Docker Hub's. A reference that is not local is pulled. |
| `NAME` | Name of the new machine. |
| `--backend BACKEND` | How to assemble it. Default: like the source. |
| `--network NETWORK` | Networks of the new machine, as for [start](#start). Default: the source's kind; a network made with `network create` is not inherited, as ports and labels are not. |
| `--network-alias [NETWORK=]NAME` | Other names of the machine on its networks, as for [start](#start). |
| `-p`, `--publish [IP:]HOST:CONTAINER[/udp]` | Ports to publish on the host, like `start -p`. Not inherited from the source. |
| `--entrypoint PROGRAM` | Replace the image's entrypoint and drop its cmd, so only the arguments given follow it; an empty string runs the arguments alone. An app left with nothing to run is refused with `no command specified`. App images only. |
| `-e`, `--env VAR[=VALUE]` | Environment for the program, `VAR=value` or `VAR` copied from the calling shell. App images only. |
| `-v`, `--volume SOURCE:TARGET[:ro]` | Mount a host directory or a named volume; `z`, `Z`, a propagation, `nocopy` and `cached` are taken and do nothing. |
| `-l`, `--label KEY=VALUE` | Label the machine, on top of the image's own labels. Not inherited from the source. |
| `--restart`, `-m`, `--memory-swap`, `--cpus`, `--pids-limit` | Restart policy and limits, as for [start](#start). Not inherited from the source. |
| the healthcheck options, the other options, `--env-file`, `--label-file`, `--mount`, `--ip`, `--gpus`, `--interface`, `--secret`, `--depends-on` | As for [start](#start). Not inherited from the source; a fixed address cannot be shared, so a copy gets one of its own. |
| `-f`, `--force` | Replace an existing machine with the same name. |
| `--no-verify` | Skip the signature check of an image that has to be pulled (a local source is not checked). |
| `-- ARGUMENTS...` | App images: replace the image's cmd; they follow its entrypoint. |

## build

```text
nspawn build [DIRECTORY|-] [-t TAG]... [-f DOCKERFILE] [--build-arg KEY[=VALUE]]... [--target STAGE]
             [--no-cache] [--no-cache-filter STAGE]... [--pull] [--label KEY=VALUE]...
             [--network MODE] [--add-host HOST:IP]... [--allow ENTITLEMENT]... [--secret id=ID[,src=PATH]]...
             [--shm-size SIZE] [--ulimit NAME=SOFT[:HARD]]... [-q] [--progress TYPE] [--iidfile FILE]
             [--push] [--no-verify] [--backend BACKEND] [--mode MODE] [--force]
nspawn build [DIRECTORY] -t TAG [-n NAME] [-d DISTRIBUTION] [-r RELEASE]
             [--profile PROFILE]... [--backend BACKEND] [--mode MODE] [--force]
             [--keep-output] [-- MKOSI_ARGS...]
```

Builds an image from a Dockerfile, or with mkosi from an
mkosi configuration, and makes it available locally, ready to push. A
directory with a `Dockerfile` (or `dockerfile`, `Containerfile`), `-f`, `-` or
any Dockerfile option makes it a Dockerfile build, run by nspawn's own
builder; a directory with `mkosi.conf` or `mkosi.conf.d` and no Dockerfile, or
an mkosi option, an mkosi build, which needs mkosi. See
[Building images](/docs/building/).

| Option | Meaning |
| --- | --- |
| `DIRECTORY` | The build context: a directory with a Dockerfile, or an mkosi configuration. `-` reads a context tar, or a Dockerfile with no context, from standard input. Default: `.`. |
| `-t`, `--tag TAG` | Reference for the result, for example `myapp:1` or `hub.example/team/app:2`. Repeatable for a Dockerfile; an mkosi build takes one, and needs it. A Dockerfile build without one fills the cache and prints the image ID. |
| `--force` | Replace an existing image with the same name. |
| `--backend`, `--mode` | As for `pull`. |
| `-f`, `--file PATH` | The Dockerfile. Default: `Dockerfile`, `dockerfile` or `Containerfile` in the context; `-` reads it from standard input. |
| `--build-arg KEY[=VALUE]` | A build argument; `KEY` alone takes it from the environment. Repeatable. |
| `--target STAGE` | The stage to build. Default: the last one. |
| `--no-cache` | Build every step again instead of taking it from the cache. |
| `--no-cache-filter STAGE` | Build these stages again. Repeatable. |
| `--pull` | Ask the registry for the base images again even when they are here. |
| `--label KEY=VALUE` | A label for the image. Repeatable. |
| `--network MODE` | The network of RUN steps: `default` (the bridge), `none`, or `host` (with `--allow network.host`). |
| `--add-host HOST:IP` | A line for the hosts file of RUN steps; `host-gateway` is the host's address on the bridge. Repeatable. |
| `--allow ENTITLEMENT` | `network.host` lets a step use `--network=host`. Repeatable. |
| `--secret id=ID[,src=PATH\|,env=VAR]` | A secret for `RUN --mount=type=secret`, read by the command line as the caller; `env=` wins over a file, and with neither the variable named `ID` when it is set, else the file. Repeatable. |
| `--shm-size SIZE` | Size of `/dev/shm` in RUN steps: `64m`, `1g`. |
| `--ulimit NAME=SOFT[:HARD]` | A resource limit of RUN steps. Repeatable. |
| `--platform PLATFORM` | The platform to build for; this host's is the only one. |
| `-q`, `--quiet` | Print only the image ID. |
| `--progress auto\|plain\|tty\|quiet` | How to show the steps; all print every line. |
| `--iidfile FILE` | Write the image ID to this file. |
| `--push` | Push the tags once built. |
| `--load` | Taken: the image is local already. |
| `--no-verify` | Pull the base images without verifying their signatures. |
| `-n`, `--name NAME` | mkosi: local image name. Default: derived from the tag. |
| `-d`, `--distribution DISTRIBUTION` | mkosi: distribution to build (`mkosi --distribution`). |
| `-r`, `--release RELEASE` | mkosi: release to build (`mkosi --release`). |
| `--profile PROFILE` | mkosi: profile to enable; repeatable. |
| `--keep-output` | mkosi: keep the output directory instead of deleting it after the import. |
| `-- MKOSI_ARGS...` | mkosi: extra arguments passed verbatim. |

`--rm`, `--force-rm`, `-m`, `--memory-swap`, `-c`, `--cpu-period`,
`--cpu-quota`, `--cpuset-cpus`, `--cpuset-mems`, `--compress`, `--squash`,
`--isolation` and `--security-opt`, which Makefiles still give, are taken and
ignored, three of them (`--isolation`, `--security-opt`, `--squash`) with a
warning; `--cache-from` is taken and ignored with a
note. `--ssh`, `-o`/`--output`, `--cache-to`, `--build-context`,
`--check`, `--call` and `--attest` are refused, and so are `--sbom` and
`--provenance` unless they ask for none (`=false`).

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

Manage local images; without a subcommand, list them.

### images ls

```text
nspawn images ls [--json]
nspawn images [--json]
```

Lists the local images known to systemd-machined: name, type, and for the ones
nspawn installed the backend, origin (`pull`, `build` or `create`), source
reference, size and whether the image is read-only. `--json` prints the list as
the service returns it. `images list` is an alias, and `images` without a
subcommand prints the same list.

### images prune

```text
nspawn images prune [-a] [-f] [--filter KEY=VALUE]...
```

Removes images no machine uses: with `-a` every
image no machine was made from; without, the dangling ones, which nspawn's
store has none of, since a tag pulled or built again replaces its record. Here
an image is a record that was pulled or built and never started. `--filter` takes
`label=KEY`, `label=KEY=VALUE` and `until=DURATION` or unix seconds,
repeatable; `-f` skips the question.

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

Removes machines: the record, the tree, the unit files, the
boot link a restart policy made, and the layers and blobs nobody else uses.
Every name is tried; one that cannot be removed, or that nothing is behind
(`no machine or image named NAME`), is reported at the end. Named volumes are
kept, and each one kept is mentioned.

A machine that others depend on (`--depends-on`) or take their network from
(`--network container:NAME`) is refused, unless they are named in the same
command: they are removed first and the machine after them; if one of them
cannot go (it runs and `-f` is not given), the machine stays too.

| Option | Meaning |
| --- | --- |
| `-f`, `--force` | Stop a running (or restarting) machine first, with SIGKILL, instead of refusing it. |

## ps, machines ls

```text
nspawn ps [-a] [-q] [-f KEY=VALUE]... [--format FORMAT] [--no-trunc] [--json]
nspawn machines ls [-a] [-q] [-f KEY=VALUE]... [--format FORMAT] [--no-trunc] [--json]
```

Lists the running machines: name, image, mode, command,
state, uptime, leader PID, network and OS. A machine whose restart policy is
bringing it back shows as `restarting`, even without `-a`. `-a`, `--all` also
lists the nspawn machines that are not running: `stopped`, or `starting` and
`closing` while their unit comes up or goes down. `--json` prints what the service returns for
each machine, its whole record included. `machines list` is an alias of
`machines ls`.

| Option | Meaning |
| --- | --- |
| `-q`, `--quiet` | The names alone, one per line. |
| `-f`, `--filter KEY=VALUE` | Only the machines that match: `name` (a regular expression), `label`, `status`, `network`, `ancestor`, `health`, `exited`, `volume`, `publish`, `expose`, `id`, `before`, `since`. The same key twice matches either value, different keys all. Repeatable. |
| `--format FORMAT` | A Go template over each machine's fields (`.Names`, `.Image`, `.Command`, `.CreatedAt`, `.RunningFor`, `.Ports`, `.State`, `.Status`, `.Labels`, `.Label "KEY"`, `.Mounts`, `.Networks`, `.Mode`, `.Address`, `.OS`, `.Pid`); `table TEMPLATE` for aligned columns with headers, `json` for an object per line. |
| `--no-trunc` | Show `.Command`, `.Mounts` and `.Image` whole; otherwise the command is cut to 20 characters, each mount to 15, and the image's digest is left out. |

## inspect

```text
nspawn inspect [-f FORMAT] NAME...
```

Prints everything nspawn knows about machines or images, running or not, as a
JSON array with one object per name: the record (image
reference, digest, backend, mode, networks, addresses, aliases, ports, volumes,
environment, command, labels, restart policy, limits, healthcheck, secrets,
the machines it depends on (`depends_on`), the other flags, and who signed the
image and when, as the pull verified it:
`signed_by`, `signed_at`), for a running machine its state, start time, leader
PID, OS and health, and for a stopped one the exit code of its last run. The keys are
those of the
[D-Bus interface](https://github.com/nspawn/nspawn/blob/master/docs/DBUS.md).
`-f`, `--format FORMAT` prints a Go template over each object instead, a
line each (`{{.state}}`, `{{json .labels}}`, `{{index .addresses "front"}}`),
with the functions `json`, `join`, `split`, `lower`, `upper`, `title`, `pad`
and `truncate`; an empty one prints the JSON.

## generate

```text
nspawn generate [NAME...]
```

Prints the nspawn commands that make machines again, on another host or on
this one, as a shell script: `network create` for the networks they join, then
`run -d --pull always` for each machine with every flag it keeps, after the
machines it depends on or takes its network from, which come along when they
are not named. An image without flags of its own is pulled again instead,
unless another machine takes its network. Without names it covers every
machine nspawn has. What a flag cannot carry is said in comments at the top:
secrets, encrypted for this host, which `nspawn secret create` makes again on
the other one; host directories a machine mounts; images built on this host,
which have to be pushed first; a healthcheck in exec form, which comes back as
`--health-cmd`. The contents of volumes and of a machine's writable layer, and
the addresses the bridge handed out, stay behind; an address fixed with `--ip`
comes along. See
[The same machines on another host](/docs/machines/#the-same-machines-on-another-host).

| Option | Meaning |
| --- | --- |
| `NAME...` | Machines to make again. Default: every machine of nspawn's. |

## start

```text
nspawn start NAME [--network NETWORK]... [--network-alias [NETWORK=]NAME]... [-p [IP:]HOST:CONTAINER[/udp]]...
             [--entrypoint PROGRAM] [-e VAR[=VALUE]]... [-v SOURCE:TARGET[:ro]]... [-l KEY=VALUE]...
             [--restart POLICY] [-m SIZE] [--memory-swap SIZE] [--cpus N] [--pids-limit N]
             [--health-cmd COMMAND] [--health-interval DURATION] [--health-timeout DURATION] [--health-retries N]
             [--health-start-period DURATION] [--health-start-interval DURATION] [--no-healthcheck]
             [--hostname NAME] [-u USER[:GROUP]] [-w DIR] [--cap-add CAP]... [--cap-drop CAP]... [--privileged]
             [--read-only] [--tmpfs PATH[:OPTIONS]]... [--shm-size SIZE]
             [--device HOST[:CONTAINER[:rwm]]]... [--dns IP]... [--dns-search DOMAIN]...
             [--add-host HOST:IP]... [--ulimit NAME=SOFT[:HARD]]... [--oom-score-adj N]
             [--stop-signal SIGNAL] [--stop-timeout SECONDS] [--timezone MODE] [--log-driver DRIVER] [--init] [--sysctl KEY=VALUE]...
             [--interface IFACE]... [--secret NAME[:TARGET[:MODE[:UID:GID]]]]...
             [--depends-on NAME[:CONDITION][:optional]]... [--env-file FILE]... [--label-file FILE]...
             [--mount type=TYPE,source=SRC,target=DST]... [--ip [NETWORK=]IP]... [--gpus REQUEST]... [--image-command] [--no-wait]
             [-- ARGUMENTS...]
```

Boots an image as a machine. Every option is remembered for the next start.

| Option | Meaning |
| --- | --- |
| `--network NETWORK` | Network of the machine: `bridge`, the default network (the default); the name of a network made with [network create](#network-create); `veth`, a veth pair configured by systemd-networkd on the host (booted images only); `host`, the host's own network; `none`, no interface but `lo`; or `container:NAME`, the network namespace of that running machine (app images only; see [container:NAME](/docs/networking/#containername)). Repeatable for several bridge networks, the first one primary: its address is where published ports lead and its gateway the default route, unless it is internal, in which case the first network that is not has the route. `veth`, `host`, `none` and `container:NAME` go alone. |
| `--network-alias [NETWORK=]NAME` | Another name for the machine on its primary network, or on `NETWORK`: every member of that network resolves it. Repeatable; `none` forgets them. |
| `-p`, `--publish [IP:]HOST:CONTAINER[/udp]` | Publish a port on the host: on every IPv4 and IPv6 address of the host, or on `IP` alone (`127.0.0.1:8080:80`, `[::1]:8080:80`); `0.0.0.0` is every IPv4 address, `[::]` every IPv6 one. `8000-8010:8000-8010` publishes a range, one mapping per port. Repeatable; `none` forgets them all. |
| `--ip [NETWORK=]IP` | A fixed IPv4 address on the primary network, or on `NETWORK`: one made with [network create](#network-create), inside its subnet and nobody else's there. Repeatable, once per network. |
| `--entrypoint PROGRAM` | Replace the image's entrypoint and drop its cmd, so only the arguments given follow it; an empty string runs the arguments alone. An app left with nothing to run is refused with `no command specified`. App images only. |
| `-e`, `--env VAR[=VALUE]` | Environment for the program, `VAR=value` or `VAR` copied from the calling shell. Repeatable; `none` forgets them. App images only. |
| `--env-file FILE` | Variables from a file of `KEY=VALUE` lines (no quoting, no expansion, `#` comments, a `KEY` alone copied from the calling shell), before the `-e` that follow and win. Repeatable. |
| `-v`, `--volume SOURCE:TARGET[:ro]` | Mount a host directory or a named volume (`z`, `Z`, a propagation, `nocopy` and `cached` are taken and do nothing), made on first use (or made ahead and still empty) with what the image has at `TARGET`, owner and files included. Repeatable; `none` forgets them. |
| `--mount type=bind\|volume\|tmpfs,source=...,target=...` | The long form of `-v` and `--tmpfs`: `readonly`, `tmpfs-size`, `tmpfs-mode`; a volume needs its name, and image, cluster or npipe mounts, `volume-subpath` and driver options are refused. Repeatable. |
| `-l`, `--label KEY=VALUE` | Label the machine, on top of the image's own labels. Repeatable; `none` forgets them. |
| `--label-file FILE` | Labels from a file of `KEY=VALUE` lines, before the `-l` that follow and win. Repeatable. |
| `--restart no\|on-failure[:N]\|always\|unless-stopped` | Restart policy; the count of `on-failure` is taken and not kept. `always` and `unless-stopped` also start the machine at boot; `nspawn stop` takes an `unless-stopped` machine off the boot list until the next `start`. Applied at the next start; [update](#update) changes it at once. |
| `-m`, `--memory SIZE` | Memory limit of the whole machine: `512m`, `2g` (at least `4m`), and as much swap again unless `--memory-swap` says otherwise; `0` removes it. Applied at the next start; [update](#update) changes it at once. |
| `--memory-swap SIZE` | Memory and swap together: equal to `--memory` for no swap, larger for the difference, `-1` for swap without a bound; `0` goes back to as much swap again as memory. Needs `--memory`. Applied at the next start; [update](#update) changes it at once. |
| `--cpus N` | CPU limit of the whole machine: `0.5`, `2`; `0` removes it. Applied at the next start; [update](#update) changes it at once. |
| `--pids-limit N` | Most processes and threads the machine may have (at least 16 for a booted machine); `0` or `-1` removes the limit. Applied at the next start; [update](#update) changes it at once. |
| `--health-cmd COMMAND` | Command that says whether the machine is healthy, run inside it as its user through `/bin/sh -c` at every interval: exit 0 is healthy. Replaces the image's `HEALTHCHECK`. [update](#update) changes it at once. |
| `--health-interval DURATION` | Time between probes: `10s`, `1m30s`, `500ms`. Default: `30s`. |
| `--health-timeout DURATION` | Time a probe may take before it counts as failed. Default: `30s`. |
| `--health-retries N` | Consecutive failed probes that make the machine unhealthy. Default: 3. |
| `--health-start-period DURATION` | Time after the start during which failed probes do not count. Default: `0s`. |
| `--health-start-interval DURATION` | Time between probes during the start period. Default: `5s`. |
| `--no-healthcheck` | No probes, whatever the image says. |
| `--hostname NAME` | Hostname inside the machine. Default: its name. A booted machine gets it as its `/etc/hostname`. |
| `-u`, `--user USER[:GROUP]` | User the program runs as, a name or a uid (listed in the image's `passwd` or not), instead of the image's, with a group after a colon: a name of the image's `group` file or a number, which becomes the primary and only group of the program; a name the image lacks is refused. nspawn resolves both from the image's `passwd` and `group` files through a stand-in for getent; a uid the `passwd` lacks runs with group 0 and `/` as home. `exec` takes it too unless its own `-u` says otherwise. App images only. |
| `-w`, `--workdir DIR` | Working directory of the program, instead of the image's. App images only. |
| `--cap-add CAP` | Capability to keep on top of the default set (for an app on a bridge network, the set [App machines](/docs/machines/#app-machines) lists, SYS_BOOT included; systemd-nspawn's for a machine in a user namespace): `NET_ADMIN`, `CAP_NET_ADMIN`, `ALL`. Repeatable; `none` forgets them. |
| `--cap-drop CAP` | Capability to drop from the default set. `--cap-drop ALL --cap-add X` keeps `X`. Repeatable; `none` forgets them. |
| `--privileged` | Every capability; `--privileged=false` takes it back. |
| `--read-only` | Mount the machine's root read-only; `--read-only=false` takes it back. |
| `--tmpfs PATH[:OPTIONS]` | An empty tmpfs at a path inside (`/tmp:size=64m,mode=0700`), 1777 when given without options. One on or below `/run`, a tmpfs of every machine already, is left out with a note. Repeatable; `none` forgets them. |
| `--shm-size SIZE` | Size of `/dev/shm`: `64m`, `1g`; `0` for the default. |
| `--device HOST[:CONTAINER[:rwm]]` | A device node of the host for the machine (`/dev/ttyUSB0:/dev/ttyUSB0:rw`), or a directory whose nodes are allowed one by one (`/dev/dri`), or a CDI name (`nvidia.com/gpu=all`) for the devices of the host's specs. Repeatable; `none` forgets them. |
| `--gpus REQUEST` | GPUs of the host's CDI specs: `all`, a count, or `'"device=0,1"'`, for the NVIDIA spec's devices (the AMD one when only that is there); `driver=` says which. See [GPUs and CDI devices](/docs/machines/#gpus-and-cdi-devices). Repeatable; `none` forgets them. |
| `--dns IP` | DNS server for the machine, instead of the host's. Repeatable; `none` forgets them. |
| `--dns-search DOMAIN` | DNS search domain, in an app's `resolv.conf` and a booted machine's `.network` file. Repeatable; `none` forgets them. |
| `--add-host HOST:IP` | A line for the machine's `/etc/hosts`, `HOST:IP` or `HOST=IP` (the second for an IPv6 address); `host-gateway` is the host's address on the machine's network. Repeatable; `none` forgets them. |
| `--ulimit NAME=SOFT[:HARD]` | A resource limit of the program (`nofile=1024:4096`, `core=unlimited`). Repeatable; `none` forgets them. |
| `--oom-score-adj N` | OOM score adjustment of the machine, -1000 to 1000. |
| `--stop-signal SIGNAL` | Signal `stop` sends the program, instead of the image's (`SIGTERM`). |
| `--stop-timeout SECONDS` | Seconds `stop` waits after the signal before SIGKILL, unless `-t` says otherwise; `-1` waits for as long as the program takes. Default: 10. |
| `--timezone MODE` | How systemd-nspawn sets the machine's `/etc/localtime` at each start, its `Timezone=`: `auto` (the default, the host's zone), `off` (left alone, so a zone set inside stays), `copy`, `bind`, `symlink` or `delete`. `auto` forgets the setting. |
| `--log-driver DRIVER` | Where the program's output goes: `local` (the default: journald's `nspawn` namespace, a journal of nspawn's own apart from the system's, capped at 1 GiB, which `logs` and an attached `run` read), `journal` (the system's journal) or `none` (dropped; `logs` refuses the machine, an attached `run` of an app still shows the output straight from the program, and a booted machine runs with `-d`). |
| `--init`, `--init=false` | The program under systemd-nspawn's stub init, which reaps orphans and turns a poweroff into SIGTERM, or as PID 1 of the machine. Without either, PID 1 for an image that carries s6-overlay, the stub init otherwise. App images only. |
| `--sysctl KEY=VALUE` | A `net.*` sysctl for an app machine's network namespace, after the two it gets by default, `net.ipv4.ping_group_range=0 2147483647` and `net.ipv4.ip_unprivileged_port_start=0`, so that a user other than root can ping without raw sockets and bind a port below 1024. Repeatable; `none` forgets them. |
| `--interface IFACE` | A network interface of the host, moved into the machine while it runs and given back when it stops: an ethernet one, or a wifi adapter with its whole phy (`iw` on the host for an app on the bridge, systemd 256 for a booted machine); the name is kept inside. Not with `--network host` or `container:NAME`; one machine at a time. See [Physical interfaces](/docs/networking/#physical-interfaces). Repeatable; `none` forgets them. |
| `--secret NAME[:TARGET[:MODE[:UID:GID]]]` | A secret made with [secret create](#secret-create) as a read-only file inside the machine: `NAME` alone is `/run/secrets/NAME` with mode 0444, root's. Repeatable; `none` forgets them. Not on `mstack` machines. |
| `--depends-on NAME[:CONDITION][:optional]` | Another machine of nspawn's to start first, like compose's `depends_on`, and what to wait for: `started` (the default: its start went through), `healthy` (its healthcheck says healthy; it needs one) or `completed` (its program ended with 0; it runs until one run of it succeeds, a run of an earlier boot counting by the exit code the journal kept, and is ordered before the machine, not wanted by it). With `:optional` a failure of it is a warning and the machine starts anyway. systemd keeps the order, at boot and for a restart policy as well. See [Dependencies](/docs/machines/#dependencies). Repeatable; `none` forgets them. |
| `--image-command` | Forget the remembered entrypoint and arguments and run the image's own again. |
| `--no-wait` | Do not wait for a booted machine's init to be up before returning. Its registration is still awaited, so that ports and firewall rules can be applied. |
| `-- ARGUMENTS...` | App images: replace the image's cmd; they follow its entrypoint. |

A path inside the machine, the target of `-v` or `--secret`, a `--tmpfs` or a
`--device` path, must be plain: a `.` or `..` component is refused.

## run

```text
nspawn run [-d] [--rm] [-i] [-t] [-n NAME] [--pull missing|always|never]
           [--backend BACKEND] [--mode MODE] [-f] [--no-verify] [OPTIONS OF start] [--no-wait]
           REFERENCE [COMMAND [ARGUMENT...]]
```

Makes a machine from an image and starts it: `pull` (or
`create` from a local image with the same reference) followed by `start`, whose
options are remembered as after `start`. A name without a registry is looked
for here under the configured registry, then as Docker Hub's
(`docker.io/library/NAME`), and pulled from the configured registry only when
neither is there. What `pull` or `create` report goes to
standard error, so that standard output carries the program's output alone.

Without `-d`, `run` stays attached. The machine's output
follows until the machine ends, a line at a time, stdout and stderr together:
it is read from nspawn's journal, so `nspawn logs NAME` shows it later too, and
the machine goes on should `run` be interrupted. With `--log-driver none` it
comes straight from the program instead, and nothing is kept. `run` exits with the program's
exit code, or 128 plus the signal nspawn sent it (130 after Ctrl-C, 137 after
`kill`); a signal from elsewhere (a crash, a kill from inside, Ctrl-C with `-t`)
gives 255, or 1 for a program that is PID 1, as systemd-nspawn ends then. Ctrl-C, SIGTERM, SIGHUP and SIGQUIT are passed on to the program; a
third Ctrl-C within a second leaves the machine running and returns. A booted
image shows its console until it powers off, and Ctrl-C powers it off.

| Option | Meaning |
| --- | --- |
| `REFERENCE` | `[registry/]repository[:tag\|@digest]`, for example `nginx:1.27`. |
| `COMMAND [ARGUMENT...]` | App images: replace the image's cmd and follow its entrypoint; everything after the reference that is not an option of `run`, or everything after `--`, which a command that starts with a dash needs. |
| `-d`, `--detach` | Start the machine in the background and return; `nspawn logs -f NAME` follows its output. |
| `--rm` | Remove the machine once it ends, with or without `-d`; named volumes stay. An image the run had to pull is kept under the image's local name when that name is free, and without `--name` the machine gets a name of its own (`alpine-3-1f0c9a2e`). Refused with a restart policy. A run that fails to start leaves nothing behind. |
| `-i`, `--interactive` | App images: give the program this standard input. Not with `-d`. |
| `-t`, `--tty` | App images: give the program a terminal; Ctrl-C and resizes reach it through the terminal. Closing the terminal stops the machine. With `-i` on a booted image: wait for it to boot, open a root shell, and power it off when the shell ends, with the shell's exit code. Not with `-d`. |
| `-n`, `--name NAME` | Name of the machine. Default: derived from the reference, for example `nginx-1.27`. A name that is taken is refused, with a pointer to `start`. |
| `--pull missing\|always\|never` | When to ask the registry. `missing`, the default: a local image with the same reference is made into the machine, as `create` does, and the registry is asked only when there is none. `always`: every time, for the image the tag names now. `never`: a local image or nothing. |
| `--backend auto\|overlay\|flat\|mstack` | How to assemble the machine, as for `pull`. |
| `--mode auto\|boot\|app` | As for `pull`; a mode other than `auto` always pulls. |
| `-f`, `--force` | Make the machine anew when one of that name exists; it must be stopped. |
| `--no-verify` | Skip the signature check of the image, as for `pull`. |
| the options of `start` | `--network`, `--network-alias`, `--ip`, `-p`, `--entrypoint`, `-e`, `--env-file`, `-v`, `--mount`, `-l`, `--label-file`, `--restart`, `-m`, `--memory-swap`, `--cpus`, `--pids-limit`, the healthcheck options, the other options, `--gpus`, `--interface`, `--secret`, `--depends-on` and `--no-wait` (with `-d` only), as for [start](#start). Options may come before or after the reference, as long as they come before the command. |

## stop

```text
nspawn stop NAME... [-f] [-t SECONDS] [--no-wait]
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
| `-t`, `--timeout SECONDS` | App images: seconds to wait after the stop signal before killing the machine; a negative number waits for as long as the program takes. Default: the machine's `--stop-timeout`, else 10. |
| `--no-wait` | Return right after the stop request, without waiting for the machine to be gone and without the kill after the timeout. |

## restart

```text
nspawn restart NAME... [-t SECONDS]
```

Stops and starts machines: a [stop](#stop) followed by
a [start](#start) with everything the machine remembers, and prints each name
once it runs again. A machine that is not running is started. Every name is
tried; one that could not be restarted is reported at the end.

| Option | Meaning |
| --- | --- |
| `-t`, `--timeout SECONDS` | As for `stop`. |

## kill

```text
nspawn kill [-s SIGNAL] NAME...
```

Sends a signal to running machines and prints each name
once it is sent. SIGKILL, the default, stops the machine for good, as
`stop --force` does. Any other signal goes to the program of an app or the
init of a booted machine and counts as a stop that keeps the
restart policy from bringing the machine back, unless the machine has a stop
signal of its own (its image's `STOPSIGNAL` or `--stop-signal`) and this is
another one: then the policy decides, should the signal end it. For a booted
machine, SIGRTMIN+3 and SIGRTMIN+4 (halt and poweroff) count as a stop. Right
after a start it waits a few seconds at most for the program to be running.

| Option | Meaning |
| --- | --- |
| `-s`, `--signal SIGNAL` | A name (`KILL`, `SIGHUP`, `RTMIN+3`) or a number. Default: `KILL`. |

## pause, unpause

```text
nspawn pause NAME...
nspawn unpause NAME...
```

`pause` freezes every process of running machines through the cgroup freezer
of their units, and `unpause` thaws them; each name is
printed once done. `ps` and `inspect` show a frozen machine as `paused`, and
`stop` and `kill` thaw it first.

## update

```text
nspawn update NAME... [--restart POLICY] [-m SIZE] [--memory-swap SIZE] [--cpus N] [--pids-limit N]
              [--health-cmd COMMAND] [--health-interval DURATION] [--health-timeout DURATION] [--health-retries N]
              [--health-start-period DURATION] [--health-start-interval DURATION] [--no-healthcheck]
```

Changes the restart policy, the limits and the healthcheck of machines,
and prints each name once changed. A running machine gets the
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
status. A paused machine is refused at once.

| Option | Meaning |
| --- | --- |
| `-u`, `--user USER[:GROUP]` | User inside the machine, a name or a number of its passwd file, with a group of its group file after a colon (then the only group; otherwise the user's supplementary groups come along) and the home of the passwd entry. Default: the machine's user, its `--user` or else its image's `USER`; root on a booted machine. |
| `-e`, `--env VAR[=VALUE]` | A variable for the command, `VAR=value` or `VAR` copied from the calling shell. Repeatable. |
| `-w`, `--workdir DIR` | Working directory of the command, instead of the machine's. |
| `-T`, `--no-tty` | No terminal, even from one: pipes, as in a script. Without `-t` or `-T`, a terminal only when standard input and output are one, so redirected output is byte-exact. |
| `-t`, `--tty` | A terminal for the command, even without one here. |
| `-i`, `--interactive` | Accepted and ignored: the command's input is always this one. |
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

Lists the processes of a running machine: `PID` as the
host sees it, `USER` as the machine sees it, `TIME` of CPU and `COMMAND`,
read from the machine's cgroup and PID namespace.

## wait

```text
nspawn wait NAME...
```

Waits for machines to stop and prints each one's exit code, a line per name;
a machine already stopped gives the code of its last run.

## port

```text
nspawn port NAME [PRIVATE_PORT[/PROTO]]
```

Prints the ports a running machine publishes
(`80/tcp -> 0.0.0.0:8080`, and `80/tcp -> [::]:8080` on a host with IPv6), or
only those of one port of the machine; one it does not publish is an error.

## cp

```text
nspawn cp MACHINE:PATH DESTINATION
nspawn cp SOURCE MACHINE:PATH
```

Copies files and directories between the host and a machine.
The machine may be running, or stopped if it is an overlay or flat
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

Shows what machines printed. With several machines every
line carries its machine's name (`web | ...`). The lines come from nspawn's
journal namespace (`--log-driver local`, the
default) and from the system's journal, which holds systemd's lines and what a
machine with `--log-driver journal` writes. A machine started with `--log-driver none`
keeps nothing, and `logs` says so (a booted one's own journal is still there
with `--inside`).

| Option | Meaning |
| --- | --- |
| `-f`, `--follow` | Keep printing new output; starts from the last 10 lines unless `--lines` says otherwise. |
| `-n`, `--lines N`, `--tail N` | Only the last N lines, or all of them with `all`. |
| `--since WHEN` | Only output newer than this: a duration ago (`42m`, `1h30m`), unix seconds, an RFC 3339 time or date, or a time as journalctl reads it (`-1h`, `"10 min ago"`, `"2026-09-24 10:00"`). |
| `--until WHEN` | Only output older than this, in the forms `--since` takes; nothing is followed then. |
| `-t`, `--timestamps` | Prefix every line with its timestamp. |
| `--all` | Also show what systemd says about the machine's service: start, stop, failures. |
| `--inside` | Booted machines only: read the machine's own journal instead of its console output. |

## stats

```text
nspawn stats [NAME...] [--no-stream] [--json]
```

Shows what running machines use: CPU (100% is one CPU
busy), memory in use against the limit (the host's memory without one),
network and disk traffic, and processes, read from the cgroup of each machine's
unit, which holds the whole machine. Without names it shows every running
machine. The table is drawn again every second on a terminal.

| Option | Meaning |
| --- | --- |
| `--no-stream` | Print one table, from two readings a second apart, and return. |
| `--json` | One JSON object per machine and reading instead of the table. |

## auto-update

```text
nspawn auto-update [--dry-run] [--json] [NAME...]
```

Moves the machines labelled `org.nspawn.auto-update=registry` (or
`io.containers.autoupdate=registry`), all of them or the ones named, to the
image their tag points to now: each is made anew with
every option it had, and put back on the old image when it does not come up
(healthy, with a healthcheck). Prints a table, `UNIT CONTAINER IMAGE
POLICY UPDATED`, with `false`, `pending`, `true`, `failed`, `rolled back` or
`skipped`, and fails when a machine failed or went back. Built images,
references pinned by digest, `run --rm` machines, booted, flat and mstack
machines, and machines whose image declares a volume none of their own volumes
covers are `skipped`; the reason goes to standard error for a machine named on
the command line, and is in `--json` always. See
[auto-update](/docs/docker-api/#auto-update).

| Option | Meaning |
| --- | --- |
| `--dry-run` | Only say which machines have a newer image waiting. |
| `--json` | One JSON object per machine. |

## events

```text
nspawn events [--since WHEN] [--until WHEN] [-f KEY=VALUE]... [--json]
```

Reports what happens to machines, networks, volumes and secrets:
for machines `start`, `die` (with its exit code), `stop`,
`restart`, `oom` and `fail`, which systemd logs for every machine however it
was started, `health_status` (with the new status) and what nspawn does,
`pull`, `build`, `create`, `push`, `kill`, `update`, `pause`, `unpause`,
`auto-update` and `remove`; for networks `create`, `remove`, `connect` and
`disconnect`; for volumes and secrets `create` and `remove`. It reads the journal, so
past events can be read back.

| Option | Meaning |
| --- | --- |
| `--since WHEN` | Events since this time: a duration ago (`42m`, `1h30m`), unix seconds, an RFC 3339 time or date, or a time as journalctl reads it (`"2026-09-24 10:00"`, `-1h`, `today`). Without it, only new ones. |
| `--until WHEN` | Stop at this time instead of waiting for new events, in the forms `--since` takes; needs `--since`. |
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
nspawn network create NAME [--subnet CIDR] [--internal] [--label KEY=VALUE]...
```

Makes a network of its own: a bridge `nsbr-NAME`
(hashed when the name is long) with its NAT and firewall rules, brought up at
once. Machines of one network reach each other by name, and nothing of another
network, the default one included, reaches them; ports they publish are
reachable from everywhere through the host, as from the LAN.

| Option | Meaning |
| --- | --- |
| `NAME` | 1 to 64 letters, digits, `_` and `-`, not starting with `-`; not `bridge`, `host`, `veth`, `none` or `default`. |
| `--subnet CIDR` | The network's IPv4 subnet. Default: the next free /24 of `network_pool` (see [Configuration](/docs/configuration/)), never one the host already routes. |
| `--internal` | No way out: its machines reach each other and the host, nothing beyond, and cannot publish ports. |
| `--label KEY=VALUE` | Label the network. Repeatable. |

### network inspect

```text
nspawn network inspect NAME...
```

Prints networks as a JSON array: name,
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

### network connect

```text
nspawn network connect [--alias NAME]... [--ip ADDRESS] NETWORK MACHINE
```

Joins a machine to a network: a running app or
booted machine gets an interface on it at once (`hostN`, with its address; the
default route stays, unless the machine had none and the network leads out),
and from its next start it joins the network as if `--network` had named it. `--alias` gives it another name there, repeatable; `--ip` a fixed
address, on a network made with `network create`. Not for a machine on host
networking, veth, another's network or none, nor an mstack one.

### network disconnect

```text
nspawn network disconnect [-f] NETWORK MACHINE
```

Takes a machine off a network: a running one
loses the interface at once. Leaving the primary network makes the next one
primary; the only network a machine has cannot be left. `-f` makes it no error
when the machine or its membership is not there.

### network prune

```text
nspawn network prune [-f] [--filter FILTER]...
```

Removes every network no machine uses, after asking on standard input unless
`-f` is given. `--filter label=KEY[=VALUE]` or `until=TIME` (a duration ago, or
unix seconds) keeps it to the networks it selects; repeatable, every one must
hold.

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

Removes every volume no machine uses once a yes comes on standard input:
from a script, whose input ends without one, nothing is removed.
`-f` removes them without asking.

## secret

Secrets, kept encrypted on the host with
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
nspawn secret create NAME [-f FILE] [-l KEY=VALUE]...
```

Keeps a secret read from standard input, or from `-f/--file`, encrypted for this
host: bound to its TPM2 where there is one, to its credential key otherwise,
under `/var/lib/nspawn/secrets`. A name that exists already is refused.

| Option | Meaning |
| --- | --- |
| `NAME` | Letters, digits, `_`, `.` and `-`, at most 64, not starting with a dot. |
| `-f`, `--file FILE` | Read the content from this file instead of standard input. |
| `-l`, `--label KEY=VALUE` | Label the secret. Repeatable. |

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

## system

### system df

```text
nspawn system df [-v] [--json]
```

What images, machines, volumes and the build cache take on disk, and what a
prune would give back. `-v` lists each of them with
its size, `--json` prints the service's answer.

### system prune

```text
nspawn system prune [-a] [--volumes] [-f] [--filter KEY=VALUE]...
```

Removes stopped machines made from an image (by `create` or `run`), networks
no machine uses and the build cache no image shares, after asking
unless `-f` is given; `-a` also removes
every image no machine was made from and the whole build cache. A `label=`
filter leaves the build cache alone.
`--volumes` asks for anonymous volumes too, which nspawn has none of: it is
accepted with a note. `--filter` takes `label=KEY`, `label=KEY=VALUE` and
`until=DURATION` or unix seconds.

## builder

### builder du

```text
nspawn builder du [-v] [--json]
```

What the build cache holds, most recently used first: the total and what is
reclaimable, `-v` every row.

### builder prune

```text
nspawn builder prune [-a] [-f] [--filter until=DURATION]... [--keep-storage SIZE]
```

Removes build cache: without `-a` the cache
entries no image shares, with `-a` all of them. `--filter until=` keeps what was used since, `--keep-storage SIZE`
keeps the most recently used cache up to that size (`64m`, `2g`), and `-f`
skips the question.

## compose

```text
nspawn compose [OPTIONS] COMMAND [ARGS...]
```

Runs docker compose files on nspawn's machines, with the commands `config`,
`up`, `down`, `create`, `start`, `stop`, `restart`, `kill`, `pause`, `unpause`,
`rm`, `run`, `exec`, `ps`, `ls`, `logs`, `top`, `port`, `images`, `pull`,
`build`, `scale`, `wait`, `cp`, `stats`, `events`, `volumes` and `version`,
each with docker compose's flags. `nspawn compose
COMMAND --help` prints each one's options. See [Compose](/docs/compose/).

## daemon

```text
nspawn daemon [--install] [--idle-exit SECONDS]
```

Serves `org.nspawn` on the system bus. The bus starts it on demand, so this is
not a command to type; `--install` is.

| Option | Meaning |
| --- | --- |
| `--install` | Write the bus policy, the polkit actions, the activation file and the unit that let the bus start this binary on demand, the units of the Docker API socket and of auto-update (its timer disabled), and the journald configuration of nspawn's log namespace, then return. A package installs the same files. |
| `--idle-exit SECONDS` | Exit after this long without a call or a running job. Default: 60; `0` keeps serving. |

## completions

```text
nspawn completions bash|elvish|fish|powershell|zsh
```

Writes the completions for that shell on standard output. Commands and flags
come from the same definition the command line itself is built from; besides
them, TAB completes names, asked from the service as it goes:

| After | TAB offers |
| --- | --- |
| `stop`, `exec`, `kill`, `pause`, `unpause`, `top`, `shell`, `stats`, `port` | the running machines |
| `start` | the images that do not run |
| `rm`, `inspect`, `generate`, `logs`, `restart`, `update`, `wait`, `auto-update`, `images rm`, `--depends-on`, the machine of `network connect` and `network disconnect` | every machine and image |
| `create`, `push` | the local images |
| `run` | the references of the local images |
| `--network` | the networks, and `host`, `none` and `veth` |
| `network rm`, `network inspect`, `network connect`, `network disconnect` | the networks |
| `volume rm` | the volumes |

The service hands those names to any user without asking polkit, so this works
under `sudo` and without a password; secrets are not completed. The flags come
once the word starts with `-` (`-` brings the short forms, `--` the long ones),
or where there is no name to offer. The packages install the completions, so
this is for a binary you built yourself:

```shell
nspawn completions bash > ~/.local/share/bash-completion/completions/nspawn
```

`man nspawn` is generated from the same definitions as the completions, with
the `--help` texts.

### Unit hooks

`nspawn network prepare NAME`, `nspawn network publish NAME` and
`nspawn network release NAME` are what the drop-in of
`systemd-nspawn@NAME.service` runs as `ExecStartPre`, `ExecStartPost` and
`ExecStopPost`, preceded by `nspawn await-dependencies NAME` for a machine
with `--depends-on`, and `nspawn health-run NAME` is what
`nspawn-health-NAME.service` runs to probe a machine's healthcheck. `nspawn
attach-exec NAME -- ...` is the drop-in's `ExecStart=`, `nspawn api-serve NAME`
is what `nspawn-api@NAME.service` runs, and `nspawn remove-after-exit` removes a
`run --rm` machine. They are not meant to be typed and are hidden from `--help`.
