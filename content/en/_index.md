---
title: nspawn
description: Docker-like management of systemd-nspawn machines
params:
  body_class: td-navbar-links-all-active
---

{{% blocks/cover title="nspawn" height="max td-below-navbar" color="primary" %}}

<!-- prettier-ignore -->
Docker-like management of systemd-nspawn machines.
Images from an OCI hub, shared layers, and systemd all the way down.
{.display-6}

<!-- prettier-ignore -->
<div class="td-cta-buttons my-5">
  <a {{% _param btn-lg primary %}} href="docs/getting-started/">
    Get started
  </a>
  <a {{% _param btn-lg secondary %}}
    href="{{% param github_project_repo %}}"
    target="_blank" rel="noopener noreferrer">
    Source on GitHub
    {{% _param FA brands github "" %}}
  </a>
</div>

{{% blocks/link-down color="info" %}}

{{% /blocks/cover %}}

{{% blocks/lead color="white" %}}

nspawn pulls OCI images from [the hub](docs/images/#the-hub) at
`hub.nspawn.org`, from Docker Hub or from any other registry, stores them as
shared layers and starts, inspects and stops the machines through the D-Bus
APIs of systemd-machined and systemd itself.

{{% /blocks/lead %}}

{{% blocks/section color="primary" type="row" %}}

{{% blocks/feature title="Images from any registry" icon="fa-cloud-arrow-down" url="docs/images/" url_text="Images and the hub" %}}

`nspawn search fedora` looks on the hub and on Docker Hub at once;
`nspawn pull` fetches from either, and `login` keeps credentials per registry.
Layers are downloaded once, verified against their digests and shared between
machines. Remove an image and the layers nobody uses go with it.

{{% /blocks/feature %}}

{{% blocks/feature title="Machines and apps" icon="fa-server" url="docs/machines/" url_text="Running machines" %}}

Images that ship systemd boot like `machinectl start` does. Anything else, for
example a docker image, runs its entrypoint as an app under a stub init, with
`-p`, `-e`, `-v`, `--label`, `--restart`, `-m` and `--entrypoint` as in docker.
`ps`, `inspect`, `exec`, `shell`, `cp`, `logs`, `stop` and `rm` work the same on
both.

{{% /blocks/feature %}}

{{% blocks/feature title="Networking that works everywhere" icon="fa-network-wired" url="docs/networking/" url_text="Networking" %}}

A docker0 style bridge with NAT, fixed addresses, published ports and machine
names that resolve, managed by nspawn itself. It behaves the same whether the
host runs systemd-networkd, NetworkManager, docker, firewalld or nothing at
all.

{{% /blocks/feature %}}

{{% /blocks/section %}}

{{% blocks/section color="white" %}}

<div class="td-home-commands">

## The whole tool in a screenful

```shell
sudo nspawn hub ls                 # repositories and tags on the hub
sudo nspawn search fedora          # images on the hub and on Docker Hub
sudo nspawn login docker.io -u me  # credentials for a registry (the hub by default)
sudo nspawn pull fedora:44         # download and assemble an image
sudo nspawn images ls              # local images (all of them, not only ours)
sudo nspawn start fedora-44        # boot it as a machine
sudo nspawn create fedora-44 db    # another machine from the same image
sudo nspawn start web -p 8080:80 -e KEY=v -v /srv/data:/data -v pgdata:/var/lib/pg
sudo nspawn start db --restart unless-stopped -m 512m   # back when it dies, and at boot
sudo nspawn ps                     # running machines: image, mode, command, uptime
sudo nspawn inspect web            # everything about a machine, as JSON
sudo nspawn cp ./nginx.conf web:/etc/nginx/
sudo nspawn exec fedora-44 -- systemctl is-system-running
sudo nspawn shell fedora-44
sudo nspawn logs fedora-44         # console output; --inside reads its journal
sudo nspawn stop fedora-44
sudo nspawn rm -f db               # remove a machine, stopping it first
sudo nspawn images rm fedora-44    # also frees layers and blobs nobody uses
sudo nspawn volume ls              # named volumes and who uses them

sudo nspawn build -t team/app:1 ./app   # mkosi --format=oci, imported as an image
sudo nspawn push team/app:1             # upload it; layers already there are skipped
```

Every command is a call to nspawn's service on the system bus, which asks
polkit who you are: `sudo` always works, an administrator is asked for a
password, and a rule of your own can hand the actions to a group.

</div>

{{% /blocks/section %}}

{{% blocks/section color="secondary" type="row" %}}

{{% blocks/feature title="Build with mkosi, push anywhere" icon="fa-hammer" url="docs/building/" url_text="Building images" %}}

`nspawn build` runs mkosi with `--format=oci` on a directory with a
`mkosi.conf`, imports the result as a local image and `push` uploads it to the
hub or to any registry you point it at.

{{% /blocks/feature %}}

{{% blocks/feature title="Open images" icon="fab fa-github" url="https://github.com/nspawn/mkosi-definitions" url_text="mkosi definitions" %}}

Every image on the hub is built from public mkosi definitions with the
distribution's own package manager. Read them, rebuild them, send fixes.

{{% /blocks/feature %}}

{{% blocks/feature title="Small and self-contained" icon="fa-feather" url="docs/overview/" url_text="How it fits together" %}}

One binary, written in Rust. Its state lives under `/var/lib/nspawn`, its
machines under `/var/lib/machines`, and everything it generates is a plain
systemd unit or settings file you can read.

{{% /blocks/feature %}}

{{% /blocks/section %}}
