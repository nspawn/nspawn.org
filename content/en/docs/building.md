---
title: Building images
linkTitle: Building
weight: 7
description: >-
  Building an image from a Dockerfile with nspawn's own builder, or with mkosi,
  through nspawn build, and uploading it to the hub or another registry with
  push.
---

`build` builds a Dockerfile the way `docker build` does, or runs mkosi on an
mkosi configuration. A directory with a `Dockerfile` (or `dockerfile`,
`Containerfile`), `-f` naming one, `-` on standard input or any of the
Dockerfile flags below make it a Dockerfile build; a directory with
`mkosi.conf` or `mkosi.conf.d` and no Dockerfile, or the mkosi flags, an mkosi
build. Either result is stored like a pulled image and can be started right
away or pushed. A Dockerfile build of a tag replaces the image it built or
pulled under that reference before, as long as no machine ran from it; `--force`
replaces any other image of the name, an mkosi build's included. `-f` is the
Dockerfile, as with docker.

## Dockerfiles

```shell
sudo nspawn build [DIRECTORY|-] [-t TAG]... [-f DOCKERFILE] [--build-arg KEY[=VALUE]]...
                  [--target STAGE] [--no-cache] [--no-cache-filter STAGE]... [--pull]
                  [--label KEY=VALUE]... [--network default|none|host] [--add-host HOST:IP]...
                  [--allow network.host] [--secret id=ID[,src=PATH|,env=VAR]]...
                  [--shm-size SIZE] [--ulimit NAME=SOFT[:HARD]]... [-q] [--progress TYPE]
                  [--iidfile FILE] [--push] [--no-verify] [--platform PLATFORM] [--load]
                  [--backend BACKEND] [--mode MODE] [--force]
```

The Dockerfile is read as BuildKit's frontend reads it (a `# syntax=` of
docker/dockerfile:1, 1.N, 1.N.M or labs is taken, another frontend image is
refused), and run by a builder of nspawn's own: every stage the target needs
(`--target`, the last one otherwise), multi-stage builds, `COPY --from`, `ARG`
and `--build-arg`, `ONBUILD`, heredocs, `COPY --chown --chmod --parents
--exclude --link`, `ADD` of local archives (gzip, bzip2, xz, zstd or plain tar,
unpacked) and of http(s) URLs (`--checksum`), and `RUN --mount` of the cache,
bind, tmpfs and secret kinds. The context is the directory given. The command
line packs it as the calling user and leaves out what `.dockerignore` excludes
(`Dockerfile.dockerignore` next to the Dockerfile wins over it); `-` takes a
context tar, or a Dockerfile with no context, from standard input.

A static program built in one stage and copied into an empty image:

```dockerfile
FROM alpine:3.22 AS build
RUN apk add --no-cache gcc musl-dev
COPY hello.c /src/
RUN gcc -static -o /hello /src/hello.c

FROM scratch
COPY --from=build /hello /hello
ENTRYPOINT ["/hello"]
```

```text
$ sudo nspawn build -t hello:1 .
docker.io/library/alpine:3.22: manifest 3e9b4b680bfc with 1 layer(s)
#1 [build 1/3] RUN apk add --no-cache gcc musl-dev
#1 0.070 fetch https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/APKINDEX.tar.gz
...
#1 1.387 OK: 172 MiB in 29 packages
#1 DONE 8.5s
#2 [build 2/3] COPY hello.c /src/
#2 DONE 0.2s
#3 [build 3/3] RUN gcc -static -o /hello /src/hello.c
#3 DONE 0.2s
#4 [stage-1 1/2] COPY --from=build /hello /hello
#4 DONE 0.7s
#5 [stage-1 2/2] ENTRYPOINT [/hello]
#5 DONE 0.0s
image hello-1 is ready: nspawn run hello-1, nspawn push hello-1

$ sudo nspawn run --rm hello:1
hello from a scratch image
```

Every step runs in a root of its own, an overlay of the layers so far, and what
it changes becomes a layer. A `RUN` runs under systemd-nspawn with the
confinement of an app machine (the default capabilities, the system call
filter, no user namespace so that files keep their owners), as PID 1, in a
network namespace the build sets up on the default bridge; `RUN --network=none`
has none, and `--network=host` needs `--allow network.host`. A layer is the tar
BuildKit writes of the same tree; its gzip blob differs.

Steps that ran before with the same inputs come from the build cache, so the
same build again takes a moment and gives the same image ID:

```text
$ sudo nspawn build -t hello:1 .
#1 [build 1/3] RUN apk add --no-cache gcc musl-dev
#1 CACHED
#2 [build 2/3] COPY hello.c /src/
#2 CACHED
#3 [build 3/3] RUN gcc -static -o /hello /src/hello.c
#3 CACHED
#4 [stage-1 1/2] COPY --from=build /hello /hello
#4 CACHED
#5 [stage-1 2/2] ENTRYPOINT [/hello]
#5 DONE 0.0s
image hello-1 is ready: nspawn run hello-1, nspawn push hello-1
```

A cache entry keeps the layers its step ran on, so a `--no-cache` build of
another Dockerfile with the same first steps does not invalidate this one's
later steps.
`--no-cache` builds every step again, `--no-cache-filter STAGE` the steps of a
stage, and `--pull` asks the registry for the base images even when they are
here.

| Option | Meaning |
| --- | --- |
| `-t`, `--tag TAG` | Reference for the result; repeatable. A name without a registry is under the configured one, as `pull` reads it. Without `-t` the build fills the cache and prints the image ID. |
| `-f`, `--file PATH` | The Dockerfile; default `Dockerfile`, `dockerfile` or `Containerfile` in the context. `-` reads it from standard input. |
| `--build-arg KEY[=VALUE]` | A build argument; `KEY` alone takes it from the environment. Repeatable. |
| `--target STAGE` | The stage to build. |
| `--no-cache`, `--no-cache-filter STAGE` | Build every step, or a stage's steps, again. |
| `--pull` | Ask the registry for the base images again. |
| `--label KEY=VALUE` | A label for the image. Repeatable. |
| `--network MODE` | The network of RUN steps: `default`, `none`, or `host` with `--allow network.host`. |
| `--add-host HOST:IP` | A line for the hosts file of RUN steps; `host-gateway` is the bridge's address. Repeatable. |
| `--secret id=ID[,src=PATH\|,env=VAR]` | A secret for `RUN --mount=type=secret`, read by the command line as you. Repeatable. |
| `--shm-size SIZE`, `--ulimit NAME=SOFT[:HARD]` | `/dev/shm` and resource limits of RUN steps. |
| `-q`, `--quiet` | Print only the image ID. |
| `--progress auto\|plain\|tty\|quiet` | How to show the steps; every one prints every line. |
| `--iidfile FILE` | Write the image ID to a file. |
| `--push` | Push the tags once built. |
| `--no-verify` | Pull the base images without verifying their signatures. |
| `--platform`, `--load` | This host's platform is the only one; the image is local already. |

The flags buildx keeps for compatibility and ignores (`--rm`, `--force-rm`,
`-m`, `--memory-swap`, `-c`, `--cpu-period`, `--cpu-quota`, `--cpuset-cpus`,
`--cpuset-mems`, `--compress`, `--squash`, `--isolation`, `--security-opt`)
are taken and ignored here too, three of them (`--isolation`, `--security-opt`,
`--squash`) with buildx's warning.

A failing step ends the build with BuildKit's message,
`process "/bin/sh -c false" did not complete successfully: exit code: 1`, and
leaves nothing behind; a build whose command line goes away (Ctrl-C) stops the
same way.

### The build cache

```text
$ sudo nspawn builder du
Reclaimable:	1.112GB
Total:		1.141GB
```

`builder du -v` lists every entry, `builder prune` removes the cache entries no
image shares (`-a` all of them, `--filter until=24h`, `--keep-storage 10g`),
`system df` counts the cache and `system prune` removes it.

### Differences from docker build

No SSH forwarding (`--ssh`), no output other than a local image (`--output`,
`--cache-to`), no named, remote or git contexts, no `ADD` of a git repository, no
attestations, only this host's platform, no `RUN --security=insecure` or `RUN
--device`, and no linter (`--check`, `--call`).
Stages run one after another; `COPY --link` copies as a plain `COPY`; `/run` is
a tmpfs during a `RUN`, so what a step writes there is not kept. Each step
starts from the layers as the image keeps them, so what a layer does not carry
(ACLs and extended attributes other than file capabilities) is gone for the
next step.

## mkosi

```shell
sudo nspawn build [DIRECTORY] -t TAG [--name NAME]
                  [-d DISTRIBUTION] [-r RELEASE] [--profile PROFILE]...
                  [--backend BACKEND] [--mode MODE] [--force] [--keep-output]
                  [-- MKOSI_ARGUMENTS...]
```

`build` runs [mkosi](https://github.com/systemd/mkosi) on a directory that has
a `mkosi.conf` or a `mkosi.conf.d` (the current directory by default), with
`--format=oci`, and imports the result exactly as `pull` would import an image
from a registry. The service runs mkosi, so mkosi has to be installed where the
service finds it (`/usr/bin`). The same configuration
tree that works with mkosi on its own works here; `--distribution`,
`--release`, `--profile` and anything after `--` are passed through.

The command line that mkosi receives is:

```text
mkosi --directory=DIRECTORY --format=oci --compress-output=zstd
      --output-directory=/var/lib/nspawn/builds/mkosi-NAME-TIMESTAMP-SUFFIX
      --cache-directory=/var/lib/nspawn/cache/mkosi
      --workspace-directory=/var/lib/nspawn/cache/mkosi-workspace/mkosi-NAME-TIMESTAMP-SUFFIX
      --image-id=REPOSITORY [--distribution=...] [--release=...] [--profile=...]...
      [MKOSI_ARGUMENTS...] --force build
```

The `/` characters of the repository are replaced by `-` in the image id. The
package cache is kept between builds; the workspace is deleted at the end, and
the output directory after the import unless `--keep-output` is given.

When mkosi is done, nspawn finds the OCI layout it produced, adds a few
annotations to the manifest (`org.opencontainers.image.version` with the tag,
`org.opencontainers.image.ref.name` with the full reference, and
`org.nspawn.builder`), verifies every blob against its digest, copies the blobs
into the store and installs the image with the chosen backend, with `build` as
its origin. The image can be started right away, cloned with `create` or
pushed. The labels of its OCI configuration, which mkosi writes from
`OciLabels=`, are kept with it: `nspawn inspect` shows them as `image_labels`,
and they travel with the image when it is pushed.

A minimal configuration for a Fedora machine that boots systemd, taken from the
test suite of nspawn:

```ini
[Distribution]
Distribution=fedora
Release=44

[Output]
ImageId=e2e-built
OciLabels=org.nspawn.e2e=built

[Content]
Bootable=no
SELinuxRelabel=no
RootPassword=root
Packages=
        systemd
        systemd-networkd
        systemd-resolved
        dbus-broker
        passwd
        util-linux
```

`systemd-networkd` is what configures `host0` on the bridge, and `dbus-broker`
(or `dbus`) is what lets `shell` reach the machine's systemd. Then:

```shell
sudo nspawn build -t team/app:1 ./app
sudo nspawn start team-app-1
```

## push

```shell
sudo nspawn push IMAGE [--to REFERENCE]
```

`IMAGE` is a local image name or the reference it was pulled from or built as.
By default the image is pushed under its own reference; `--to` pushes it under
another one, for example to retag it or to send it to a different registry:

```shell
sudo nspawn push team/app:1
sudo nspawn push team-app-1 --to registry.example/team/app:2
```

`push` authenticates first, with the credentials stored for that registry, and
tells you which `nspawn login` to run when the registry wants some it does not
have. The blobs that are already on the registry are skipped and the manifest
is uploaded last. A push needs a tag, not a digest, and the image's manifest
and blobs must still be in the store (`images rm` removes them). See
[Registries and credentials](/docs/images/#registries-and-credentials).

## The hub images

The images the team publishes on `hub.nspawn.org` are built with mkosi from the
definitions in
[nspawn/mkosi-definitions](https://github.com/nspawn/mkosi-definitions). Use
them as a starting point for your own images, or open a pull request there to
change what the hub ships.
