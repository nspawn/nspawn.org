---
title: Compose
weight: 6
description: >-
  docker compose files and commands, run by nspawn compose on nspawn's machines.
---

`nspawn compose` runs docker compose files on nspawn's machines, with the
commands, flags and output of docker compose 5.6.0: in a directory with a
`compose.yaml`, `sudo nspawn compose up -d` brings the services up and
`sudo nspawn compose down` takes them away. It is a client of the
[service](/docs/overview/#the-service) like every other
command, so it takes the same permissions.

## A project

```yaml
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    depends_on:
      db:
        condition: service_healthy
  db:
    image: postgres:18-alpine
    environment:
      POSTGRES_PASSWORD: example
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 2s
    volumes:
      - db:/var/lib/postgresql
volumes:
  db:
```

In a directory `shop` with that file:

```text
$ sudo nspawn compose up -d
 Image postgres:18-alpine Pulling
 Image postgres:18-alpine Pulled
 Image nginx:alpine Pulling
 Image nginx:alpine Pulled
 Network shop_default Creating
 Network shop_default Created
 Volume shop_db Creating
 Volume shop_db Created
 Container shop-db-1 Creating
 Container shop-db-1 Created
 Container shop-web-1 Creating
 Container shop-web-1 Created
 Container shop-db-1 Starting
 Container shop-db-1 Started
 Container shop-db-1 Waiting
 Container shop-db-1 Healthy
 Container shop-web-1 Starting
 Container shop-web-1 Started

$ sudo nspawn compose ps
NAME         IMAGE                COMMAND                  SERVICE   CREATED         STATUS                   PORTS
shop-db-1    postgres:18-alpine   "docker-entrypoint.s…"   db        4 seconds ago   Up 3 seconds (healthy)
shop-web-1   nginx:alpine         "/docker-entrypoint.…"   web       3 seconds ago   Up Less than a second    0.0.0.0:8080->80/tcp, [::]:8080->80/tcp

$ sudo nspawn compose exec db psql -U postgres -c 'select 1'
 ?column?
----------
        1
(1 row)
```

The services are nspawn's machines, and every other command sees them:

```text
$ sudo nspawn ps
 MACHINE     IMAGE                                 MODE  COMMAND                                   STATE              UP  PID    NETWORK                              OS
 shop-db-1   docker.io/library/postgres:18-alpine  app   docker-entrypoint.sh postgres             running (healthy)  3s  19093  shop_default:10.99.1.2               Alpine Linux v3.24
 shop-web-1  docker.io/library/nginx:alpine        app   /docker-entrypoint.sh nginx -g daemon...  running            0s  19262  shop_default:10.99.1.3 8080->80/tcp  Alpine Linux v3.24
```

`sudo nspawn compose down -v` stops and removes the machines, the network and,
with `-v`, the volume.

## How a project becomes machines

- A service becomes a machine per replica, named `PROJECT-SERVICE-N` with `_`
  written `-`. The machines carry the `com.docker.compose.*` labels, which is
  how `ps`, `logs`,
  `stop`, `down` and the rest find a project again, from its files or from
  `-p NAME` alone.
- An image that names no registry comes from Docker Hub and is kept under its
  local name (`postgres:18-alpine` is `postgres-18-alpine`); every machine of
  it is made from that image.
- A network of the project is an nspawn [network](/docs/networking/#networks-of-your-own),
  `PROJECT_KEY`, and a volume an nspawn [volume](/docs/machines/#volumes), also
  `PROJECT_KEY`. A secret or config from a file is bound read-only where the
  service reads it; one from the environment or written in the file is an
  nspawn [secret](/docs/machines/#secrets), removed by `down`.
- A volume without a source, or a `VOLUME` of the image nothing of the service
  mounts over, is an nspawn volume named after the machine, `MACHINE_anon_HEX`.
  A machine made anew finds its own again; `up -V` makes new ones, and `down -v`
  and `rm -v` remove them.
- A network whose definition changed since `up` made it is made anew, with the
  project's machines on it.
- `depends_on` orders what compose does: `up`, `start`
  and `run` bring the services up in order and wait for their conditions, and
  `restart` also restarts the services whose `depends_on` sets `restart: true`. The machines carry no
  `--depends-on`, so nspawn does not keep a service that others depend on from
  being made anew, scaled down or removed. With `-p NAME` and no `-f`, `down`,
  `stop`, `logs` and the other commands that act on what runs take the project
  from the labels, a compose file in the directory or not: the labels say what
  depends on what, so `down SERVICE` takes the services that depend on it too.
  With the files it takes that service alone.
- A machine is made anew when its service changed, which its
  `com.docker.compose.config-hash` label records, or its image did.
- A bind source that is missing is made by compose, which runs as you. One
  under a directory you cannot look into (`/etc/letsencrypt/live` for anyone
  but root) is left to the service, which runs as root and mounts it, or
  refuses it when it is not there either.

## Builds

A service with a `build` section is built by nspawn's
[builder](/docs/building/#dockerfiles): when its
image is not here (an image it names is pulled first, and built when the pull
fails), every time with `pull_policy: build`, and always with `up --build` or
`compose build`; `--no-build` builds nothing. Its image is the one it names or
`PROJECT-SERVICE`. A name without a registry or a namespace is nspawn's own,
under the configured registry as `nspawn build -t` puts it, so
`sudo nspawn run NAME` takes it; one like `user/app` stays Docker Hub's, where
`compose build --push` sends it. `down --rmi local` removes the images the
project built.

## The commands

`config`, `up`, `down`, `create`, `start`, `stop`, `restart`, `kill`, `pause`,
`unpause`, `rm`, `run`, `exec`, `ps`, `ls`, `logs`, `top`, `port`, `images`,
`pull`, `build`, `scale`, `wait`, `cp`, `stats`, `events`, `volumes` and
`version`, each with its flags. `alpha`, `attach`, `bridge`, `commit`,
`export`, `publish`, `push` and `watch` are refused with an error that names an
alternative where there is one; `--dry-run` is refused by the commands that
change something, as nothing simulates their changes.

## What is supported

The files load with interpolation, `.env`, profiles, `include`, `extends`,
overrides, `!reset` and `!override`, and the schema's checks, with docker
compose's messages; `sudo nspawn compose config` prints the project as
loaded. What nspawn cannot do (remote build
contexts, SSH forwarding into a build, Swarm-only attributes) `config` shows as
warnings, and `up`, `create`, `run` and `scale` refuse it for the services they
start.

[COMPOSE.md](https://github.com/nspawn/nspawn/blob/master/docs/COMPOSE.md)
lists every attribute and option with what nspawn compose does with it: yes,
partly (with the difference), ignored with a warning, or refused with the
reason.
