---
title: The Docker API
weight: 8
description: >-
  The Docker Engine API on a socket of the host and in each machine that mounts
  docker's socket, for the docker command, CI runners, reverse proxies and
  dashboards, and auto-update of the machines whose tag points to a newer image.
---

nspawn serves the Docker Engine API, 1.51 and any version down to 1.24 a client
asks for, on a socket of the host and in each machine that mounts docker's
socket. Clients make, start, attach to, exec in, copy files to and from and
remove containers, pull and remove images, and make, join and remove volumes and
networks. The server is a client of the [service](/docs/overview/#the-service),
as the command line is: every change it makes is a method of `org.nspawn`, under
the same polkit actions, and what it makes is a machine like any other, which
`nspawn ps` shows.

## The host's socket

The packages ship it turned off:

```shell
sudo systemctl enable --now nspawn-api.socket
export DOCKER_HOST=unix:///run/nspawn/api.sock
```

Every user may connect to `/run/nspawn/api.sock`, and polkit decides what each
one may do, with the service's actions: reads and waits ask for
`org.nspawn.inspect`, logs and changes for `org.nspawn.manage`, `_ping` and
`version` for nothing. polkit is never asked to prompt, since nothing on a socket
answers an authentication agent: a user other than root needs a rule, such as
`nspawn-wheel.rules`, which the packages ship as an example. Root may do
everything.

Then the `docker` command works with it:

```text
$ docker pull busybox:1.37
1.37: Pulling from library/busybox
docker.io/library/busybox:1.37: manifest 66a6306db78b with 1 layer(s), assembling as overlay
68fe9bff2ad4: Already exists
30ecbe150909: Already exists
Digest: sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec
Status: Downloaded newer image for busybox:1.37
docker.io/library/busybox:1.37
$ docker run --rm busybox:1.37 echo hello
hello
$ docker run -d --name web -p 8080:80 busybox:1.37 httpd -f -p 80 -h /tmp
c7dac8ca487657695c14e21240f15fd99e7eac48d6c13e770febe7b0ac74d31e
$ echo hello > index.html && docker cp index.html web:/tmp/index.html
$ curl -s http://127.0.0.1:8080/
hello
$ docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
NAMES     IMAGE          STATUS                  PORTS
web       busybox:1.37   Up Less than a second   0.0.0.0:8080->80/tcp, [::]:8080->80/tcp
$ docker exec web sh -c 'id; pwd'
uid=0(root) gid=0(root)
/
$ sudo nspawn ps
 MACHINE  IMAGE                           MODE  COMMAND                 STATE    UP  PID      NETWORK                 OS
 web      docker.io/library/busybox:1.37  app   httpd -f -p 80 -h /tmp  running  0s  2814430  10.99.0.3 8080->80/tcp  -
```

Volumes and networks are nspawn's:

```text
$ docker volume create data
data
$ docker network create back
68735561ab7cd7e4da9b248b9c68ff65d4518c05d1730d79056e8dd3c2dc8eda
$ docker network connect back web
$ docker run --rm --network back -v data:/data busybox:1.37 sh -c 'wget -qO- http://web/ | tee /data/page'
hello
$ docker run --rm -v data:/data busybox:1.37 cat /data/page
hello
```

On a host without docker, clients that only look at `/run/docker.sock` or
`/var/run/docker.sock` find the socket there with a drop-in:

```shell
sudo mkdir -p /etc/systemd/system/nspawn-api.socket.d
printf '[Socket]\nSymlinks=/run/docker.sock\n' | sudo tee /etc/systemd/system/nspawn-api.socket.d/docker.conf
sudo systemctl daemon-reload && sudo systemctl restart nspawn-api.socket
```

### GitLab Runner

GitLab Runner's docker executor runs its jobs through the socket: the clone, the
job's image, services with their aliases, artifacts, cache volumes and a network
per build (`FF_NETWORK_PER_BUILD`). In its `config.toml`:

```toml
[[runners]]
  executor = "docker"
  [runners.docker]
    host = "unix:///run/nspawn/api.sock"
    image = "alpine:3.22"
```

The runner runs as root, or as a user that a polkit rule lets through.

## What it serves

- `_ping`, `version`, `info` and `system df`.
- Containers: list, inspect, logs, stats, top, events; create, start, stop,
  restart, kill, pause, unpause, wait, update, remove and prune. A create's
  settings become the machine's options. What nspawn has no use for is named in
  the answer's `Warnings` (`CpuShares`, `SecurityOpt`, a logging driver other than
  `json-file`, `local`, `journald` or `none`, among others); what would change what
  the container does is refused with 400 (`PidMode`, `IpcMode` or `UTSMode` of the
  host, a user namespace mode, another runtime, `VolumesFrom`, an IPv6 address).
- Attach, with the input: `docker run -i`, `docker run -it` and `docker start -ai`
  give the program their input, and an attach that keeps the input gets the output
  byte for byte.
- Exec: a terminal or the two streams apart, the input, variables, working
  directory and user. On a terminal, the end of the input or the client's hangup
  sends the command SIGHUP.
- Copies: `docker cp` both ways, on running containers and on stopped ones, owners
  and modes kept. A volume of a stopped container is mounted only while it runs, so
  a copy to or from it is refused until it starts.
- Images: list, inspect, history, pull (`POST /images/create`), remove and prune.
  A record pulled or built that never ran is an image, not a container; a machine
  made from it is a container. An image's ID is its config's digest.
- Volumes and networks: list, inspect, create, remove and prune; connect and
  disconnect with aliases and fixed addresses. `bridge`, `host` and `none` are the
  pre-defined networks.

Builds, loads, imports, tags, pushes and commits of images, container renames and
exports, swarm and plugins answer 501 with "not supported".

A name the API takes that is no machine name, such as `reaper_1`, stays the
container's name in the API, and its machine gets one made of it (`reaper-1-` and
eight hex digits), which `nspawn ps` shows. A network keeps the name the API gave
it the same way.

## docker's socket in a machine

A machine that mounts `/var/run/docker.sock`, `/run/docker.sock` or
`/run/nspawn/api.sock` from the host gets nspawn's Docker API there instead of the
host's docker, with `-v /var/run/docker.sock:/var/run/docker.sock` or compose's
`use_api_socket`. Mounted read-write, it takes every request the API serves:

```text
$ sudo nspawn run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    docker.io/library/docker:28.5.1-cli -- docker run --rm busybox:1.37 echo from-a-machine
docker-28.5.1-cli-6fd52594: 10 layer(s) shared with docker-28.5.1-cli, assembling as overlay
from-a-machine
```

Mounted with `:ro`, it reads, follows logs and kills, and refuses any other change
with 403:

```text
$ sudo nspawn run --rm -v /var/run/docker.sock:/var/run/docker.sock:ro \
    docker.io/library/docker:28.5.1-cli -- docker run --rm busybox:1.37 true
docker-28.5.1-cli-c46d6cef: 10 layer(s) shared with docker-28.5.1-cli, assembling as overlay
docker: Error response from daemon: this machine binds nspawn's Docker API read-only

Run 'docker run --help' for more information
```

Tools that follow containers through the socket find nspawn's machines the same
way: reverse proxies that route by labels (caddy-docker-proxy, Traefik,
nginx-proxy with docker-gen and acme-companion), dashboards (homepage) and log
viewers (Dozzle). They only read, and kill to have a server read its
configuration again, so `:ro` is all they need. caddy-docker-proxy in front of a
service, from a `compose.yaml` in a directory `proxy`:

```yaml
services:
  caddy:
    image: lucaslorentz/caddy-docker-proxy:2.13-alpine
    ports:
      - "80:80"
    environment:
      - CADDY_INGRESS_NETWORKS=proxy_default
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
  whoami:
    image: traefik/whoami
    labels:
      caddy: http://whoami.example.test
      caddy.reverse_proxy: "{{upstreams 80}}"
```

```text
$ sudo nspawn compose up -d
$ curl -s -H 'Host: whoami.example.test' http://127.0.0.1/ | head -2
Hostname: proxy-whoami-1
IP: 127.0.0.1
```

A machine that has the socket sees every machine and their `-e` variables
(`--secret` values never show). Only root inside the machine can connect.

### How it is served

Each machine that takes the socket has its own, `/run/nspawn/api/NAME.sock`,
opened by systemd (`nspawn-api@NAME.socket`) before the machine starts and closed
after it stops; the host's is `nspawn-api.socket`. The server behind each,
`nspawn-api@NAME.service` or `nspawn-api.service`, starts when something connects
and leaves a minute after the last connection, the attached sessions and exec
commands of its clients included. A container ID comes from the machine's name and
creation time, so it stays across restarts and updates. nspawn binds the machine's
`/etc/hostname` from a directory named after that ID, so tools that look for their
own container in `/proc/self/mountinfo` find it.

What one socket's clients hold at once is bounded: 64 connections (one more is
closed at once), 16 of them logs, events or attach streams, each running a
`journalctl`, 16 waits and attaches, and 64 exec commands that run; one more of
any of these gets 503. On the host's socket a user other than root holds a quarter
of the connections and of the exec commands and half of the streams and of the
waits at most, so that no user keeps the others or root out, and root has 16
streams of its own. mstack machines cannot take the socket.

## auto-update

`sudo nspawn auto-update` moves the machines labelled
`org.nspawn.auto-update=registry` to the image their tag points to now.
`io.containers.autoupdate=registry` is taken too, on the machine, never from
its image, with `image` meaning `registry` and `disabled` or an empty value no
updates.

```text
$ sudo nspawn run -d --name tagged -l org.nspawn.auto-update=registry \
    docker.io/library/busybox:latest -- sleep 600
$ sudo nspawn auto-update --dry-run
 UNIT                           CONTAINER  IMAGE                             POLICY    UPDATED
 systemd-nspawn@tagged.service  tagged     docker.io/library/busybox:latest  registry  false
```

For each machine the registry is asked for the tag's digest, with a HEAD that
registries do not count against their limits. A newer image is pulled, its
signature policy included, and the machine is made anew from it with every
option it had: networks and address, ports, volumes, variables, labels,
limits, restart policy and the rest (`generate` prints the same command before
and after), and its creation time, so its Docker API ID stays. A running
machine is stopped and started again and has to come up: healthy when it has a
healthcheck, still running ten seconds after its start otherwise. When it does
not, the old image and what the machine had written are put back and it starts
again, which the table reports as `rolled back`.

A machine on the new image starts with a fresh writable layer: what it keeps
belongs in volumes. Machines that share its
network (`--network container:`) start again with it, and so do compose
services whose `depends_on` asks for `restart: true`. Built images, references
pinned by digest, `run --rm` machines, booted machines (their state is their
writable layer), flat and mstack ones, and machines whose image declares a
volume (`VOLUME`) none of their own volumes covers, whose data would stay in the
old writable layer, are left alone and show `skipped`, as the `local` policy
does; the reason goes to standard error for a machine named on the command
line, and is in `--json` always. A policy that is none of these (a misspelt
one) shows `failed`, so that the run and its timer show it.

`--dry-run` only says which machines have a newer image waiting (`pending`).
The `UPDATED` column takes `false`, `pending`, `true`, `failed`, `rolled back`
(the old image back and running) or `skipped`; `--json` prints a JSON object per machine, and the command fails
when a machine failed or went back.

The packages ship a daily timer with up to fifteen minutes of random delay,
disabled:

```shell
sudo systemctl enable --now nspawn-auto-update.timer
```
