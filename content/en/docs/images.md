---
title: Images and the hub
linkTitle: Images
weight: 3
description: >-
  Image references, the hub and Docker Hub, search and credentials, what pull
  does, the storage backends, boot and app detection, more machines from one
  image, and where everything lives on disk.
---

## References

An image reference has the form `[registry/]repository[:tag|@digest]`:

- Without a registry part, the configured registry is used. Out of the box that
  is the hub, `hub.nspawn.org`; the [configuration](/docs/configuration/) page
  shows how to change it. The first path component counts as a registry when it
  looks like a host, for example `docker.io/library/nginx` or
  `registry.example:5000/team/app`, or when it is the configured registry's own
  name, so a registry of the local network without a dot or a port (`myhub`)
  reads back as itself.
- Without a tag or digest, the tag is `latest`.
- Repository names may only contain lowercase letters, digits, `.`, `_`, `-`
  and `/`. Official Docker Hub images live under `library/`, so nginx is
  `docker.io/library/nginx`; `search` prints references in that form.

The **local name** of an image, the one `start`, `stop`, `exec` and friends
use, is derived from the reference (`fedora:44` becomes `fedora-44`) unless
`--name` says otherwise. It has to be a valid machine name: letters, digits,
`.`, `_` and `-`, at most 64 characters, not starting with a dot.

## The hub

The hub is a plain OCI registry. `nspawn hub ls` lists its repositories with
their tags, and `nspawn hub tags REPOSITORY` the tags of one of them:

```shell
sudo nspawn hub ls           # everything
sudo nspawn hub ls deb       # repositories whose name contains "deb"
sudo nspawn hub ls --no-tags # faster on big registries
sudo nspawn hub tags fedora
```

The same commands work against any registry that implements the catalog
endpoint; point them somewhere else with `--registry`, the `NSPAWN_REGISTRY`
variable or the configuration file. A private CA is trusted with `--ca-cert`
or `NSPAWN_CA_CERT`.

The images on the hub are built with [mkosi](https://github.com/systemd/mkosi)
from the public definitions in
[nspawn/mkosi-definitions](https://github.com/nspawn/mkosi-definitions), with
the package manager of each distribution, and rebuilt every week so that they
carry the current security updates. They come in three kinds:

| Kind | Images |
| --- | --- |
| Distributions | `debian`, `ubuntu`, `fedora`, `centos`, `almalinux`, `rockylinux`, `opensuse`, `archlinux`, `kali`, several releases each |
| Services | `nginx`, `apache`, `caddy`, `haproxy`, `postgresql`, `mariadb`, `redis`, `valkey`, `memcached`, `rabbitmq`, `mosquitto`, `unbound`, `dnsmasq`, `bind9`, `samba`, `openssh`, `prometheus`, `node-exporter`, `grafana`, `wordpress`, `syncthing`, `forgejo` |
| Machines to work in | `debian-devel`, `ubuntu-devel`, `fedora-devel`, `archlinux-devel`, `python`, `nodejs`, `golang`, `rust`, `openjdk` |

A service image is a whole Debian machine with that service installed and
enabled, so `shell` gets you a root shell and `systemctl status nginx` inside
tells you what it is doing. Its tags carry the version of the service
(`nginx:1.26.3`, `nginx:1.26`, `nginx:latest`), and every build also gets a
dated tag (`nginx:1.26.3-20260923`) that never moves, so a machine can be
pinned to one build. <https://hub.nspawn.org/> browses the lot.

## Searching

```shell
sudo nspawn search TERM [--source hub|dockerhub] [-n LIMIT]
```

`search` is `docker search` across the sources nspawn knows: the configured
hub (its catalog, case-insensitive substring match, with the tags of every
match) and Docker Hub (its search API). Every hit names its source and the
reference `pull` takes:

```text
 SOURCE          NAME                        DESCRIPTION                               STARS  OFFICIAL
 hub.nspawn.org  debian                      tags: 12, 13, bookworm, trixie            -      -
 Docker Hub      docker.io/library/debian    Debian is a Linux distribution that's...  5100   yes
 Docker Hub      docker.io/someone/debian-x  Debian with extras                        3      -
```

`--source` asks one side only and `-n` limits the results per source (25 by
default). A source that cannot be reached is reported as a warning, not as an
error, so the other one still answers.

## Registries and credentials

Registries are used anonymously until you log in:

```shell
sudo nspawn login                       # the hub
sudo nspawn login docker.io -u USER     # Docker Hub
echo "$TOKEN" | sudo nspawn login registry.example -u ci --password-stdin
sudo nspawn logout docker.io
```

`login` asks for the user name and the password on the terminal (without
echo), or reads the password from standard input with `--password-stdin`, and
checks them the way `docker login` does: `GET /v2/` on the registry, then basic
authentication or a token request at the realm the registry announces. Bad
credentials are refused with a clear message. A registry that never asks for
credentials gets them stored anyway, with a note saying so.

Credentials are kept in `/etc/nspawn/auth.json`, mode 0600, in the `auth.json`
format that podman and skopeo use. That file is the only one consulted: the
work happens in the service, which has no home directory of yours to look into,
so what `docker login` or `podman login` left behind does not carry over. Every
operation chooses the credentials of the registry it talks to, so the hub's
never travel to Docker Hub; the many names of Docker Hub (`docker.io`,
`index.docker.io`, `registry-1.docker.io`) are one entry.

Docker Hub limits anonymous pulls per address; logging in lifts that. `push`
authenticates before it uploads anything and, when the registry wants
credentials it does not have, says which `login` to run.

## Signed images

Every image on the hub is signed twice by the workflow that builds it
([nspawn/mkosi-definitions](https://github.com/nspawn/mkosi-definitions)) with
cosign: with the project's key, whose public half (`cosign.pub` in that
repository) is built into nspawn, and keyless, with the workflow's own identity
through Sigstore
(`https://github.com/nspawn/mkosi-definitions/.github/workflows/mkosi.yml@refs/heads/master`,
issued by GitHub). The signatures are referrers of the image on the registry:
Sigstore bundles that carry the certificate or the key's hint, the transparency
log entry and a timestamp, so `pull` verifies them offline, with nothing but the
registry consulted, against the Sigstore trusted root the binary embeds. One of
the two has to verify, and the check comes before a single layer is downloaded:

```text
$ sudo nspawn pull fedora:44
hub.nspawn.org/fedora:44: signature verified (key 6wiWMtJZCUkV, keyless https://github.com/nspawn/mkosi-definitions/.github/workflows/mkosi.yml@refs/heads/master)
hub.nspawn.org/fedora:44: manifest 9240778b2c77 with 1 layer(s), assembling as overlay
...
```

An image without a signature (a tag dated before the signing began, or one
pushed by hand with `nspawn push`) is refused with `carries no signature`, and
so is one whose signatures do not verify, with the reason of each. `--no-verify`
on `pull`, `run` and `create` skips the check for that command, like docker's
`--disable-content-trust`; `create` checks only an image it has to pull, never
a local source. `inspect` shows who signed (`signed_by`: `key <hint>, keyless
<identity>`) and when (`signed_at`), which a machine made with `create`
inherits from its source.

Images of other registries are pulled unverified until the
[configuration file](/docs/configuration/#signature-policies) says what they
must carry, one table per registry; the same table can require other keys of
the hub, or turn its check off:

```toml
[registries."hub.nspawn.org"]
verify = false
```

The policies belong to the service: `--registry` on the command line chooses
the registry, never the policy.

## Pulling

```shell
sudo nspawn pull REFERENCE [--name NAME] [--backend BACKEND] [--mode MODE] [--force] [--no-verify]
```

It resolves the reference to the manifest for the host's
platform (image indexes are followed), checks the image's signatures where its
registry has a policy (the hub's is built in; see
[Signed images](#signed-images)) before anything is downloaded, downloads every
layer and the config blob that is not already in the store, three at a time as docker does, checking
each one against its sha256 digest while it streams (a blob is written next to
its final name and renamed only once verified, so an interrupted download never
passes for a complete one, and a download cut short takes its part file with
it), says of each blob when it is downloaded, and then:

1. assembles the root file system with the chosen [backend](#backends);
2. reads the OCI config and decides whether the image is a
   [boot or an app image](#boot-and-app-images);
3. writes `/etc/systemd/nspawn/NAME.nspawn`, the settings the machine boots
   with, and the drop-in that makes `systemd-nspawn@NAME.service` call nspawn
   around its life;
4. records the image (reference, manifest digest, layers, backend, mode,
   network, who signed it) under `/var/lib/nspawn`, and keeps the manifest and blobs so that
   the image can be pushed or cloned later.

An image with the same name is not replaced unless you pass `--force`, and
never while its machine is running, starting or being restarted by its policy. The old image only goes once the new one
is downloaded, and the store is locked only for that last step, so a long
download holds up neither other commands nor the unit hooks.

## Backends

The backend decides how the layers become a directory systemd-nspawn can boot:

| Backend | What it does | Needs |
| --- | --- | --- |
| `overlay` | Layers are extracted once under `/var/lib/nspawn` and shared. Each machine gets an overlayfs mount at `/var/lib/machines/NAME`, defined by a generated mount unit, with a private upper directory for its writes. | Any systemd with overlayfs. |
| `mstack` (experimental) | A native `systemd.mstack` directory at `/var/lib/machines/NAME.mstack` that points at the shared layers; the machine boots with managed user namespaces (`PrivateUsers=managed`) and the layers are shifted into the foreign UID range. Only when asked for by name, with a note that it is experimental: systemd-nsresourced and systemd-mountfsd are still settling, and what the host's systemd makes of a managed user namespace is its business (the 262 release cannot boot one at all until the fix for [systemd/systemd#43899](https://github.com/systemd/systemd/issues/43899) lands in a later version). | systemd 261 or newer with the `systemd-nsresourced` and `systemd-mountfsd` sockets available (nspawn starts them). |
| `flat` | The layers are extracted into a plain directory at `/var/lib/machines/NAME`. Nothing is shared, maximum compatibility. | Nothing. |
| `auto` (default) | `overlay` when overlayfs is available, otherwise `flat`. Never `mstack`. | |

Pick one per image with `--backend` on `pull`, `build` or `create`, or set a
default in the configuration file. `nspawn images ls` shows which backend each
image uses. On `create`, `auto` means the backend of the image it comes from,
not the chain above.

App images are always assembled as `overlay` (or `flat`), even where `mstack`
is available: a machine under managed user namespaces cannot join the network
namespace nspawn prepares for apps on the bridge. `pull` says so with a note
when it makes that choice.

## Boot and app images

After assembling, nspawn looks at the root file system and at the OCI config:

- An image that ships an **init program** (`usr/lib/systemd/systemd`,
  `lib/systemd/systemd`, `sbin/init` or `usr/sbin/init`, as the topmost layer
  leaves it) and whose entrypoint is that init, or has no entrypoint at all, is
  a **boot** image. It is started with `Boot=yes`, as `machinectl start` would.
- Everything else is an **app** image: the entrypoint and command from the
  config run under nspawn's stub init (`Boot=no`, `ProcessTwo=yes`), with the
  config's environment, working directory, user and stop signal.

`--mode boot` or `--mode app` overrides the detection. The mode is recorded with
the image; [Machines](/docs/machines/) explains how it changes `start`, `exec`,
`shell` and `stop`.

## More machines from one image

```shell
sudo nspawn create SOURCE NAME [--backend BACKEND] [--network NETWORK]... [-p [IP:]HOST:CONTAINER[/udp]]...
                   [--entrypoint PROGRAM] [-e VAR[=VALUE]]... [-v SOURCE:TARGET[:ro]]... [-l KEY=VALUE]...
                   [--restart POLICY] [-m SIZE] [--cpus N] [--pids-limit N] [OPTIONS OF start] [-f] [-- ARGUMENTS...]
```

`create` is `docker create`: another machine from an image that is already
local, given by its name or by the reference it was pulled from, without
touching the registry. A reference that is not local is pulled first, under
the image's own name, as `run` does. The machine shares the source's layers
and gets a writable layer, an address, settings and a record of its own, with
`create` as its origin; `images rm` of one never affects the others.

The network kind is inherited from the source unless `--network` says
otherwise; published ports are not, since two machines cannot publish the same
one, and neither are the source's labels, restart policy, limits, variables,
volumes, healthcheck, secrets or the other flags: a new machine only gets what
its own command line gives. Every option of `start` is accepted and means the
same; `--entrypoint`, `-e` and the arguments after `--` apply to app images
only, `-v` works for both kinds. Everything on the command line is checked
before anything is made, so a refused `create` leaves nothing behind.
`pull --name` ends up the same way, but resolves the manifest through the
registry first.

## Listing and removing

```shell
sudo nspawn images ls
```

```text
 NAME       TYPE       BACKEND  ORIGIN  SOURCE                          SIZE     RO
 fedora-44  directory  overlay  pull    hub.nspawn.org/fedora:44        612 MiB  no
 db         directory  overlay  create  hub.nspawn.org/fedora:44        612 MiB  no
 web        directory  overlay  pull    docker.io/library/nginx:latest  190 MiB  no
 old-arch   directory  -        -       -                               1.2 GiB  no
```

The list comes from systemd-machined, so it includes images nspawn did not
create (`old-arch` above, with `-` in the nspawn columns). `ORIGIN` is `pull`,
`build` or `create`.

```shell
sudo nspawn images rm NAME...
```

`images rm` refuses to remove the image of a running machine, or of one its
restart policy is bringing back; `nspawn rm -f` stops it first. A pulled image
is a machine too, so `nspawn rm NAME` removes the same thing.
For an image nspawn manages it unmounts and deletes the assembled root, the
settings file, the generated units and drop-ins, the network namespace of an
app and the record; for any other image, or for the leftovers of a failed
install, it removes what it finds and asks machined to forget the rest.
Afterwards the layers and blobs that no remaining image references are
deleted, the `/etc/hosts` files of the machines on the bridge are regenerated
and the published ports are brought in line with the machines that still run.
Named volumes are not deleted: they may belong to another machine. `nspawn
volume ls` shows them and `volume rm` or `volume prune` removes the unused ones.

`images ls --json` prints the list as the service returns it.

## Where things live

| Path | Contents |
| --- | --- |
| `/var/lib/machines/NAME` | The root of a machine with the `overlay` or `flat` backend (a mount point in the first case). |
| `/var/lib/machines/NAME.mstack` | The `systemd.mstack` directory of a machine with the `mstack` backend. |
| `/var/lib/nspawn/` | nspawn's own state: blobs as downloaded, extracted layers, image records, stored manifests, the private upper directories of overlay machines, the generated network files and units of each machine, mkosi build output and cache, and the store lock. Root's alone (0700), but for the generated files an mstack machine binds from inside its user namespace; the directory itself can only be passed through (0711). |
| `/var/lib/nspawn/volumes/NAME` | A named volume (`-v NAME:/inside`). |
| `/etc/systemd/nspawn/NAME.nspawn` | The settings nspawn generates for a machine; regenerated at every `start`, mode 0600 since it carries the `-e` variables. |
| `/etc/systemd/system/systemd-nspawn@NAME.service.d/` | The drop-in with the unit hooks (and the machine's `Restart=`, `MemoryMax=`, `MemorySwapMax=`, `CPUQuota=` and `TasksMax=` when it has them) and, for an overlay machine, the one that requires its mount unit. The mount unit itself is next to them in `/etc/systemd/system/`. |
| `/etc/systemd/system/machines.target.wants/systemd-nspawn@NAME.service` | The boot link of a machine with `--restart always` or `unless-stopped`; `rm` removes it. |
| `/etc/nspawn/nspawn.toml` | The [configuration file](/docs/configuration/), optional. |
| `/usr/lib/systemd/system/nspawn.service`, `/usr/share/dbus-1/system.d/org.nspawn.conf`, `/usr/share/polkit-1/actions/org.nspawn.policy` | The service, its bus policy and its polkit actions, as a package installs them. `nspawn daemon --install` writes the unit and the bus policy under `/etc` instead, where they take precedence, and the actions in the same place as the packages. |
| `/etc/nspawn/auth.json` | The credentials `login` stored, mode 0600. |
| `/run/netns/nspawn-NAME` | The network namespace of a running app machine on the bridge. |

The state is kept outside `/var/lib/machines` on purpose: machined would list
a directory there as an image, and `machinectl clean` would delete it.
