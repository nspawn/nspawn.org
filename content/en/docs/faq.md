---
title: FAQ
weight: 9
description: >-
  Short answers to the questions that come up most.
---

## What is nspawn.org?

A hub for systemd-nspawn images and the tool that uses them. The team builds
images of common Linux distributions with [mkosi](https://github.com/systemd/mkosi),
publishes them on an OCI registry at `hub.nspawn.org`, and maintains `nspawn`,
the command line tool documented on this site. The
[mkosi definitions](https://github.com/nspawn/mkosi-definitions) of the images
are public.

## Do I need systemd?

Yes, version 255 or newer. nspawn drives systemd-nspawn through systemd-machined
and the systemd service manager, so the host needs both, with cgroup v2. The
images on the hub contain systemd as well; images without an init system run as
[apps](/docs/machines/#app-machines).

## Is this docker?

No. The commands and flags look alike on purpose (`-p`, `-e`, `-v`,
`--entrypoint`, `create`, `exec`, `logs`), but the machines are systemd-nspawn
containers managed by systemd: they are `systemd-nspawn@NAME.service` units,
appear in `machinectl list`, log to journald and boot a full init when the
image has one. nspawn's own service holds none of them open, there is no compose
file and no orchestration.

## Can I run images from Docker Hub?

Yes. `sudo nspawn search nginx` finds them, and
`sudo nspawn pull docker.io/library/nginx:latest --name web` fetches one like
any other registry image. Since it has no init system, it is installed as an
app image: its entrypoint runs under nspawn's stub init, on the bridge, with
`-p` for its ports. Docker Hub limits anonymous pulls per address;
`sudo nspawn login docker.io -u USER` lifts that. See
[Getting started](/docs/getting-started/#an-app-from-docker-hub).

## Do I need root?

Not necessarily. Every command goes through the service on the system bus, and
the service asks polkit about the caller: root is never asked, an administrator
is asked for a password (a desktop session prompts; in a plain terminal, start
`pkttyagent` first), and a rule of your own can hand the actions to a group so
that nobody is asked at all. The work does need privileges, since the machines
live below `/var/lib/machines` and the bridge is the host's, which is why the
service is the one holding them.

On a host without polkit the service answers root alone. See
[The service](/docs/overview/#the-service) for the two actions and the rule.

## What is the org.nspawn service?

Where the work happens. The command line is its client, the way `machinectl`
and `systemctl` are clients of machined and systemd: every command is a method
call, and pulls, pushes, builds, creates, removals and copies come back as job
objects that report their output. The bus starts the service when a command arrives and it exits
after a minute without work, so nothing of nspawn's runs in the background
otherwise. A package installs it; for a binary you built yourself,
`sudo nspawn daemon --install`. Its journal is `journalctl -u nspawn.service`,
and the interface is described in `docs/DBUS.md` of the repository. After an
upgrade the service keeps running the binary it started with until it goes
idle or is restarted; a command of another version says so and asks for
`sudo systemctl restart nspawn.service` (the rpm and the deb restart it
themselves).

## Are the images signed?

Yes. The workflow that builds the images of the hub, in
[nspawn/mkosi-definitions](https://github.com/nspawn/mkosi-definitions), signs
each one twice with [cosign](https://github.com/sigstore/cosign) after pushing
it: keyless, with the identity of that workflow on `master` (a short-lived
certificate from Fulcio, recorded in the Rekor transparency log), and with the
project's key, whose public half is `cosign.pub` in that repository. The
signatures are stored on the hub next to the image, as OCI referrers of its
digest, so they cover every tag that points to it, and the hub verifies the
key one itself and shows the image as signed.

`nspawn pull` verifies them too, since 1.5.0: before a single layer is
downloaded, one of the two signatures has to verify offline against the
project's key and the workflow's identity, both built into nspawn, and an
image without a valid signature is refused (`--no-verify` skips the check for
one command; see [Signed images](/docs/images/#signed-images)). Other
registries get a [policy in the configuration](/docs/configuration/#signature-policies).
To verify an image yourself, with cosign:

```shell
cosign verify \
  --certificate-identity https://github.com/nspawn/mkosi-definitions/.github/workflows/mkosi.yml@refs/heads/master \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  hub.nspawn.org/fedora:44
```

or, with the key from the repository, `cosign verify --key cosign.pub
hub.nspawn.org/fedora:44`. Every blob is also checked against the sha256
digest in the manifest while it downloads, and registries are reached over
HTTPS only.

## What happened to the wrapper script and the tar images?

The first generation of nspawn was a shell wrapper around `machinectl` that
downloaded `tar.xz` and `raw.xz` images from `hub.nspawn.org/storage`, signed
with the nspawn.org master key and verified by systemd-importd. Its last
release was 0.6; version 1.0 replaced it with the OCI based client described
here: images are OCI images on
a registry, layers are shared, and machinectl is no longer involved. The
history of the old script is still in the
[nspawn repository](https://github.com/nspawn/nspawn).

## Does the bridge work with NetworkManager, docker or firewalld?

Yes. nspawn creates the bridge, its addresses and its nftables rules itself,
and hands each machine its address through a generated file or a prepared
network namespace. Neither systemd-networkd nor NetworkManager on the host is
involved; only `--network veth` depends on systemd-networkd. With firewalld the
bridge is put in the trusted zone, and on hosts where docker or ufw set the
forward policy to drop, nspawn adds the exception the bridge needs. See
[Firewalls](/docs/networking/#firewalls).

## What is the difference between exec and shell?

`exec` enters the machine's namespaces, like `docker exec`: nothing is needed
inside, the exit code comes back and the program is found on the machine's
`PATH`. `shell` opens an interactive shell: machined's login session for a
booted machine, which needs D-Bus inside, or `/bin/sh` in the namespaces for an
app.

## How do I keep data across restarts and rebuilds?

With volumes, as in docker: `-v /srv/data:/data` mounts a host directory,
`-v pgdata:/var/lib/postgresql` a named volume that nspawn keeps under
`/var/lib/nspawn/volumes/pgdata`. Named volumes survive `rm` and `images rm`. See
[Volumes](/docs/machines/#volumes).

## Can I run several machines from one image?

Yes: `sudo nspawn create fedora-44 db` makes another machine that shares the
layers of `fedora-44` and has a writable layer, an address, ports and settings
of its own. See [More machines from one image](/docs/images/#more-machines-from-one-image).

## Can a machine start at boot?

Yes. `sudo nspawn start NAME --restart always` (or `unless-stopped`) enables the
unit and also restarts the machine when it ends; `systemctl enable
systemd-nspawn@NAME.service` (or `machinectl enable NAME`) works too. Either way
the drop-in nspawn installs on the unit prepares the network and publishes the
ports whoever starts the machine.

## How do I get a machine's address from the host?

`sudo nspawn ps` shows it, and `sudo nspawn network inspect bridge` (or the
name of another network) lists the machines of a network with their addresses. Inside the machines, the other
machines are reachable by name and the host as `host.nspawn.internal`; on hosts
with systemd 258 or newer, machined resolves the machine names on the host as
well.

## How do I free disk space?

`sudo nspawn rm NAME` (or `images rm`) removes a machine or image, and
afterwards every layer and blob that no remaining image references. Overlay
machines keep their writes in a private directory under `/var/lib/nspawn`,
which goes away with the image; named volumes stay until `sudo nspawn volume rm
NAME` or `sudo nspawn volume prune`.

## Where do I ask or report a problem?

For questions, `#nspawn-org` on [Matrix](https://matrix.to/#/#nspawn-org:matrix.org)
or on [Libera.Chat](https://web.libera.chat/#nspawn-org). For bugs, the issues
of [github.com/nspawn/nspawn](https://github.com/nspawn/nspawn/issues) for the
tool, [mkosi-definitions](https://github.com/nspawn/mkosi-definitions/issues)
for the images, and [nspawn.org](https://github.com/nspawn/nspawn.org/issues) for
this site.
