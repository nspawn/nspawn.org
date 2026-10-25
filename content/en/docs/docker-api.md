---
title: The Docker API
weight: 8
description: >-
  docker's socket for reverse proxies and dashboards, and auto-update of the
  machines whose tag points to a newer image.
---

## docker's socket in a machine

Tools that follow containers through docker's socket find nspawn's machines the
same way: reverse proxies that route by labels (caddy-docker-proxy, Traefik,
nginx-proxy with docker-gen and acme-companion), dashboards (homepage) and log
viewers (Dozzle). A machine that mounts `/var/run/docker.sock` or
`/run/docker.sock` from the host, with `-v /var/run/docker.sock:/var/run/docker.sock`
(`:ro` is taken too) or compose's `use_api_socket`, gets nspawn's Docker API
there instead of the host's docker.

It speaks the Docker API 1.51, and any version down to 1.24 a client asks for:
`_ping`, `version` and `info`, the machines as containers with their labels,
networks and addresses, inspect with the environment, events as they happen,
logs, stats and top, and the networks. Reads of images, volumes and swarm
objects get 501. It changes nothing, with one exception:
`POST /containers/ID/kill` sends a signal as `nspawn kill` does, so that
docker-gen and acme-companion can have nginx read new configuration and
certificates. Any other write is refused with 403.

caddy-docker-proxy in front of a service, from a `compose.yaml` in a directory
`proxy`:

```yaml
services:
  caddy:
    image: lucaslorentz/caddy-docker-proxy:2.13-alpine
    ports:
      - "80:80"
    environment:
      - CADDY_INGRESS_NETWORKS=proxy_default
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
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

What a client sees, from a machine that mounts the socket:

```text
$ sudo nspawn run --rm -u 0 -v /var/run/docker.sock:/var/run/docker.sock \
    docker.io/curlimages/curl:8.11.1 -- -s --unix-socket /var/run/docker.sock http://localhost/_ping
OK
$ sudo nspawn run --rm -u 0 -v /var/run/docker.sock:/var/run/docker.sock \
    docker.io/curlimages/curl:8.11.1 -- -s --unix-socket /var/run/docker.sock -X POST http://localhost/containers/create
{"message":"nspawn's Docker API is read-only: POST /containers/create is not served"}
```

A machine that has it sees every machine and their
`-e` variables (`--secret` values never show). Only root inside the machine
can connect; the curl image runs as a user of its own, hence `-u 0`, and without
it the connection is refused:

```text
$ sudo nspawn run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    docker.io/curlimages/curl:8.11.1 -- -sS --unix-socket /var/run/docker.sock http://localhost/_ping
curl: (7) Failed to connect to localhost port 80 after 0 ms: Could not connect to server
```

### How it is served

Each machine that takes the socket has its own, `/run/nspawn/api/NAME.sock`,
opened by systemd (`nspawn-api@NAME.socket`) before the machine starts and
closed after it stops. The server behind it, `nspawn-api@NAME.service`,
starts when something connects and leaves after a minute without a
connection. A container ID comes from the machine's name and creation time, so
it stays across restarts and updates. nspawn binds the machine's
`/etc/hostname` from a directory named after that ID, so tools
that look for their own container in `/proc/self/mountinfo` find it.

Each machine's API takes 64 connections at once and closes any past that. At
most 16 of them can stream logs or events, each running a `journalctl`; one more
gets 503. mstack machines cannot take the socket.

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
