---
title: Networking
weight: 5
description: >-
  The nspawn0 bridge, networks of your own, published ports, DNS and machine
  names, how apps get their network, firewalls, and the veth and host
  alternatives.
---

Every machine records which networks it uses. `start --network` changes them,
and the choice sticks for the next start.

| Network | Default for | What the machine gets |
| --- | --- | --- |
| `bridge` | Every image nspawn installs | A fixed address on the `nspawn0` bridge, NAT to the outside, published ports, the names of the other machines and of the host. Needs nothing from the host's own network manager. |
| a network's name | | The same on a bridge of its own, made with `network create`; several at once, with `--network` repeated: see [Networks of your own](#networks-of-your-own). |
| `host` | | The host's network namespace, like `docker run --network host`: the machine sees the host's interfaces and binds to the host's ports. Works for both kinds of image. |
| `none` | | No network at all, like `docker run --network none`: `lo` and nothing else. Works for both kinds of image. |
| `container:NAME` | | The network namespace of the running machine `NAME`, like `docker run --network container:NAME`: its interfaces, address, hosts file and resolv.conf, nothing of the machine's own. App images only; see [container:NAME](#containername). |
| `veth` | Images not installed by nspawn | The classic systemd-nspawn setup: a virtual ethernet pair whose host end is configured by systemd-networkd through the stock `80-container-ve.network`. Booted images only. |

## The bridge

On the first `start` of a bridged machine (or with `nspawn network up`, which
is handy at boot) nspawn creates the bridge with the first address of the
subnet, enables IPv4 forwarding and installs the nftables table `ip nspawn`
with masquerading for the subnet. The defaults are the bridge `nspawn0` and the
subnet `10.99.0.0/24`; both, and the DNS servers, can be changed in
[the configuration file](/docs/configuration/). An interface that already has
that name is only taken over when it is a bridge nspawn made, or an empty one;
`bridge = "docker0"` is refused rather than acted on. Nothing else on the host
is touched, so it works the same with systemd-networkd, NetworkManager or no
network manager at all.

Each machine gets a fixed address from the subnet, remembered with its record.
A **booted** machine receives it through a `.network` file that nspawn
generates and bind-mounts at `/run/systemd/network/10-host0.network`, for the
systemd-networkd inside to apply, together with the DNS servers: the host's
upstream resolvers by default, `dns` from the configuration if set, `--dns`
and `--dns-search` of the machine over both, and public resolvers as a last
resort, with a warning, when none can be determined.

An **app** machine has nothing inside to configure an interface, so nspawn
builds its network namespace before the program starts: `ip netns`, a veth pair
on the bridge, the address and the default route, handed to systemd-nspawn with
`NamespacePath=`, plus a generated `/etc/resolv.conf`. The namespace lives at
`/run/netns/nspawn-NAME` while the machine runs and goes away with it, and
`--sysctl` sets `net.*` keys in it.

A generated `/etc/hosts`, mounted into every bridged machine, resolves the names
of the other machines on the bridge and `host.nspawn.internal` for the host;
`--add-host HOST:IP` adds lines of your own, `host-gateway` standing for the
host's address on the machine's network. On hosts with systemd 258 or newer,
machined also lets the host resolve machine names by itself. The bridge
carries IPv4 only, so neither the machines nor the bridge get an IPv6
link-local address, and a machine's name leads to its bridge address:
`ping web` from the host answers from `10.99.0.x`.

```shell
sudo nspawn network inspect front
```

```text
[
  {
    "created": 1790331611,
    "gateway": "10.99.1.1",
    "interface": "nsbr-front",
    "internal": false,
    "labels": {
      "tier": "edge"
    },
    "machines": [
      {
        "address": "10.99.1.2",
        "aliases": [
          "www"
        ],
        "name": "web",
        "ports": [
          "127.0.0.1:8080->80/tcp"
        ],
        "running": true
      }
    ],
    "name": "front",
    "subnet": "10.99.1.0/24"
  }
]
```

## Networks of your own

Like docker's user-defined networks, `network create` makes a bridge of its own
for a group of machines:

```shell
sudo nspawn network create back --internal
sudo nspawn network create front --label tier=edge
sudo nspawn run -d --name db --network back --network-alias postgres docker.io/library/postgres:17
sudo nspawn run -d --name web --network front --network back --network-alias front=www -p 127.0.0.1:8080:80 docker.io/library/nginx:latest
```

```text
back is up: nsbr-back on 10.99.2.0/24
front is up: nsbr-front on 10.99.1.0/24
```

The bridge is `nsbr-NAME` (a hash of the name when it is too long for an
interface name), and its subnet the next /24 of `network_pool` (`10.99.0.0/16`
unless set in [the configuration file](/docs/configuration/)) that overlaps no
other network and nothing the host routes already; `--subnet` chooses one.
Machines of one network reach each other by name, through the same generated
`/etc/hosts`, and `host.nspawn.internal` is that network's gateway. Nothing
of another network reaches them, the default one included: the forward chain
of the `ip nspawn` table drops what crosses from one bridge to another, and a
drop there holds whatever firewalld or iptables allow. Ports a machine
publishes are the exception, reachable from every network through the host,
as from the LAN. `--internal` makes a network with no way out: its machines
reach each other and the host, nothing beyond, and cannot publish ports.

A machine may join several networks: `--network front --network back` puts it
on both, with an address on each, the first one primary. The primary network
is where its published ports lead and, unless it is internal, where its default
route goes; an internal primary leaves the route to the first network that is
not. A booted machine gets one interface per network (`host0`, `host1`, ...),
each configured by the systemd-networkd inside through a `.network` file of
its own; an app machine gets them in the namespace nspawn prepares. Its
`/etc/hosts` lists, for every network it is on, the members of that network
with their addresses there, so a proxy on `front` and `back` reaches both
sides while `front` and `back` still do not reach each other. `veth` and
`host` go alone.

`--network-alias NAME` gives a machine another name on its primary network,
`--network-alias NETWORK=NAME` on that network, as `docker run
--network-alias` does: every member of the network resolves the alias as well,
which is how `db` can stand for `postgres-17` today and for another machine
tomorrow. An alias several machines share leads to the first of them by name.
`--network-alias none` forgets them.

`network ls` lists the networks with the machines whose records name them,
`network inspect NAME` shows one with its machines, their addresses, aliases
and ports, and `network rm` and `network prune` remove the ones no machine
uses, bridge, rules and firewall exceptions included. `network create --label
KEY=VALUE` tags a network for whoever reads `network inspect`, as docker's
does:

```shell
sudo nspawn network ls
```

```text
 NETWORK  INTERFACE   SUBNET        INTERNAL  MACHINES
 bridge   nspawn0     10.99.0.0/24  no        bb
 back     nsbr-back   10.99.2.0/24  yes       api db web
 front    nsbr-front  10.99.1.0/24  no        web
```

The `/etc/hosts` of `web`, on `front` and `back` with `www` as its alias on
`front`, lists the members of both networks with their addresses there:

```text
# Generated by nspawn; do not edit.
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
10.99.1.2 web www
10.99.2.3 web
10.99.1.1 host.nspawn.internal
10.99.2.4 api
10.99.2.2 db postgres
```

## Published ports

```shell
sudo nspawn start web -p 8080:80 -p 5353:53/udp -p 127.0.0.1:9090:9090 -p 8000-8010:8000-8010
```

Each `-p [IP:]HOST:CONTAINER[/udp]` becomes a DNAT entry in the `ip nspawn`
table. Without an address the port is reachable from other hosts, from the
host's own addresses and from `127.0.0.1` (through `route_localnet`, as docker
does without its userland proxy); with one, `127.0.0.1:9090:9090` say, on that
address of the host alone, for a reverse proxy in front. A range,
`8000-8010:8000-8010`, is one mapping per port, which `inspect` shows one by
one. The entries are installed once the machine is registered and removed when
it ends, by the unit hooks, so they also go away after a crash or when the
program exits on its own. A port another running machine publishes, on every
address or on that one, or one a service of the host already listens on, is
refused before the machine starts, and a refused port is not remembered. On a
machine with several networks the port leads to its primary address.

The list is remembered for the machine: `nspawn start web` next time publishes
the same ports, and `-p none` forgets them all. Ports need the bridge network;
a machine on the host's network listens on the host's ports directly.

## Firewalls

- **firewalld**: the bridge is placed in the `trusted` zone at runtime, which
  also lets published ports through. The binding does not survive
  `firewall-cmd --reload`; the next `start` or `nspawn network up` puts it
  back.
- **docker** (in its default iptables mode) and **ufw** set the `FORWARD`
  policy to `DROP`, which would silence every machine on the bridge. `start`
  then adds two rules to the `DOCKER-USER` chain, which docker reserves for
  that, or to the top of `FORWARD` itself: anything out of the bridge, and into
  the bridge only what was published or belongs to a connection a machine
  opened. That needs the `iptables` command, which those tools bring with them.
- Where something else drops forwarded traffic, a hand-written nftables
  firewall or those same rules without the `iptables` command to edit them,
  `start` says so and the exception has to be made by hand. Without it the
  machines reach nothing beyond the bridge and published ports answer on this
  host alone.

## veth

`--network veth` keeps the classic systemd-nspawn behaviour for booted
machines: systemd-nspawn creates a virtual ethernet pair and systemd-networkd on
the host brings up the host end (`ve-NAME`), gives it an address, serves DHCP
to the machine and masquerades its traffic, all through the stock
`80-container-ve.network`. App images refuse it, since nothing inside would
configure the pair.

Because that needs systemd-networkd, `start` activates it when the host has no
`.network` files of its own in `/etc/systemd/network` or `/run/systemd/network`,
and refuses with an explanation when it has, so that nspawn never takes over
interfaces another network manager is handling. A masked systemd-networkd is an
error. With firewalld, `ve-NAME` is bound to the `trusted` zone while the
machine runs; otherwise the default zone would drop the machine's DHCP
requests.

## host

`--network host` sets `VirtualEthernet=no`: the machine shares the host's
network namespace, sees the host's interfaces and binds to the host's ports.
Published ports do not apply, and an app that runs this way keeps its user
namespace.

## none

`--network none` sets `Private=yes`: the machine has `lo` and nothing else,
like `docker run --network none`. Published ports do not apply, and an app that
runs this way keeps its user namespace too.

## container:NAME

`--network container:NAME` puts an app machine in the network namespace of the
machine `NAME`, docker's sidecar pattern (a VPN client with the programs that
must go through it, for one): the same interfaces and address, `NAME`'s hosts
and resolv.conf files, and nothing of the machine's own. A port the program
serves is published with `-p` on `NAME`, since that is where the address is.
`NAME` can be an app or a booted machine on any bridge network, has to be
running when the machine starts (`--depends-on NAME` has it started first, at
boot as well), and cannot be removed while a machine names it, unless that
machine goes in the same `rm`. When `NAME` stops or restarts, the machine keeps
the namespace it joined,
which then leads nowhere, and has to be restarted to join the new one, as with
docker.

```shell
sudo nspawn run -d docker.io/qmcgaw/gluetun --name vpn --cap-add NET_ADMIN --device /dev/net/tun -p 8080:8080
sudo nspawn run -d docker.io/library/nginx:1.27 --name web --network container:vpn
```

## Physical interfaces

`--interface IFACE` on `run`, `create` and `start` gives a machine a network
interface of the host, whole: a second ethernet port, or a wifi adapter for a
machine doing wireless work. `--device` cannot do it, since a network interface
is not a node under `/dev`, and `--network host` cannot either: the machines
run in a user namespace, which may not configure the host's interfaces. The
interface is moved into the machine's network namespace before its program or
init runs and is back on the host when the machine stops or is removed, with
its name kept on both sides, as systemd-nspawn's `Interface=` and LXC's `phys`
type do it. It arrives down and unconfigured, as the kernel moves it: the
machine brings it up and configures it, with `ip` in an app or its
systemd-networkd in a booted machine. The flag is repeatable and remembered
like the rest, `--interface none` forgets them, and `inspect` lists them as
`interfaces`.

```shell
sudo nspawn run -d kali:latest --name kali --interface wlp11s0f3u2u3
sudo nspawn exec kali -- iw dev
sudo nspawn stop kali          # the adapter is back on the host
```

Where systemd-nspawn makes the machine's network namespace (a booted machine,
on the bridge or with veth, and any machine with `--network none`) the
interface goes into the machine's settings file as `Interface=` and
systemd-nspawn moves it at start and back at exit. An app machine on a bridge
network gets its namespace from nspawn itself (`NamespacePath=`, which allows
no `Interface=` beside it), so the unit's hooks move the interface in with `ip`
before systemd-nspawn runs and give it back after; such an app runs without a
user namespace, so `iw reg set` and monitor mode work inside as on the host.
Either way the unit waits for the interface's device unit, so that a machine
started at boot waits for a USB adapter udev has not seen yet.

A wifi adapter cannot leave its phy, so the phy moves whole, every interface it
carries with it (nspawn says which), and a driver without namespace support
(`ath6kl`, `wilc1000`) refuses the move naming the phy. An app on the bridge
takes a wireless interface on any systemd, through `iw`, which has to be
installed on the host; `Interface=` moves a phy since systemd 256, so on an
older host a wireless interface is refused for a booted machine or one with
`--network none`, with a message that says so. The regulatory domain (`iw reg
set`) and rfkill are host-wide: they are set on the host, or from an app on
the bridge; `--device /dev/rfkill` hands the switch to such an app.

One machine at a time takes an interface: a second one naming it is refused
while the first runs (`stop` it, or start it with `--interface none`). Refused
as well: `lo`, the bridges and veth ends of nspawn's own, a port of a bridge or
bond (`ip link set IFACE nomaster` first), a name that is not on the host (a
machine that ended a moment ago may still hold it: the kernel gives interfaces
back a little after their namespace dies), a machine with `--network host`, one
with `--network container:NAME` (give the interface to `NAME`) and the mstack
backend. The interface of the host's default route is allowed with a warning,
since the host loses its route while the machine runs. When the interface
comes back, NetworkManager or systemd-networkd manage it again as before, and
a name taken on the host in the meantime makes the kernel rename it (`dev0`,
`wlan0`). `stop --force` kills the machine: an app on the bridge still gets
every interface back from its release hook, while a machine that took them
through `Interface=` may not get to give them back, and the kernel then
returns a physical interface or a wifi phy a moment later and destroys a
virtual one (a VLAN, a macvlan, a dummy) with the namespace.

Behind the scenes the service binds the name systemd-nspawn looks for
(`/run/netns/nspawn-web`) to the network namespace of `vpn`'s leader process,
the mount `ip netns attach` would make, so the settings are the ones of any
app on a bridge, and drops the name when `web` stops while the namespace
stays `vpn`'s. `-p`,
`--network-alias`, `--dns`, `--dns-search`, `--add-host` and `--sysctl` are
refused on such a machine, since they shape a network of its own, and so is a
booted image, whose systemd would configure the shared interfaces again. `ps`
and `inspect` show the network as `container:NAME`; `network inspect` does not
list the machine among the network's members, as it has no address there.
