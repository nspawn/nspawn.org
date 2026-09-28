---
title: Configuration
weight: 7
description: >-
  The configuration file, environment variables and global flags, what wins
  when they disagree, and what is remembered per machine.
---

nspawn needs no configuration to work: the defaults point at the hub, use
`/var/lib/machines` and `/var/lib/nspawn`, pick the best backend for the host
and run the bridge on `10.99.0.0/24`. Everything below is optional.

## Precedence

1. Command line flags and their environment variables (`--registry` or
   `NSPAWN_REGISTRY`, `--ca-cert` or `NSPAWN_CA_CERT`).
2. The configuration file.
3. The built-in defaults.

## The configuration file

The file is `/etc/nspawn/nspawn.toml`, read when it exists; `--config FILE` or
`NSPAWN_CONFIG` names another one, which then must exist. Every key is
optional, and unknown keys are an error so that a typo does not silently fall
back to a default.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `registry` | string | `hub.nspawn.org` | Registry for references without a host part. |
| `ca_cert` | path | none | Extra CA certificate (PEM) to trust when talking to the hub. |
| `backend` | `auto`, `overlay`, `flat` or `mstack` | `auto` | Backend for `pull` and `build` when they are not given `--backend`: `auto` is `overlay`, or `flat` without overlayfs; `mstack` is experimental. |
| `machines_dir` | absolute path | `/var/lib/machines` | Where machines are assembled. |
| `state_dir` | absolute path | `/var/lib/nspawn` | Blobs, layers, records, volumes and everything else nspawn keeps. |
| `bridge` | string, 1 to 15 letters, digits, `-` or `_` | `nspawn0` | Name of the bridge the machines join. It must be free, or a bridge nspawn made. |
| `subnet` | IPv4 CIDR, prefix 8 to 30 | `10.99.0.0/24` | Subnet of the bridge; its first address is the bridge's own. |
| `network_pool` | IPv4 CIDR | `10.99.0.0/16` | Where `network create` takes the /24 of a network given no `--subnet`: the first one that overlaps no other network and nothing the host routes. |
| `dns` | list of IPv4 addresses | the host's upstream servers | DNS servers handed to bridged machines. They must be reachable from the bridge: no loopback, no IPv6. |

An example:

```toml
# /etc/nspawn/nspawn.toml
registry = "registry.example:5000"
ca_cert = "/etc/pki/tls/certs/example-ca.pem"
backend = "overlay"

bridge = "br-lab"
subnet = "172.30.5.0/24"
dns = ["172.30.5.1", "9.9.9.9"]
```

Changing `bridge` or `subnet` affects machines started afterwards; the address
recorded for a machine is reassigned from the new subnet on its next start.

## Signature policies

What the images of a registry must carry, one table per registry (host, or
host:port). The hub's policy is built in (the project's key or the build
workflow's keyless identity, one of them required, its transparency log entry
checked): a table for `hub.nspawn.org` replaces it, and `verify = false` turns
the check off. Every other registry is verified only when it has a table.

```toml
[registries."registry.example.com"]
key = "/etc/nspawn/keys/example.pub"      # a cosign public key (PEM); keys = [...] for several
identity = "https://github.com/org/repo/.github/workflows/build.yml@refs/heads/main"
issuer = "https://token.actions.githubusercontent.com"   # goes with identity
required = true            # default: no verifying signature fails the pull
rekor = true               # default: the signature's transparency log entry must verify
trusted_root = "/etc/nspawn/trusted_root.json"   # another Sigstore deployment; the public one otherwise

[registries."hub.nspawn.org"]
verify = false             # nothing is checked for this registry
```

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `verify` | boolean | `true` | `false` turns verification off for the registry, the hub's built-in policy included. |
| `key`, `keys` | absolute path, list of absolute paths | none | Cosign public keys (PEM) the images may be signed with; `key` and `keys` add up. |
| `identity`, `issuer` | strings, both or neither | none | A keyless signer: the certificate's identity (the SAN, a URI or an email) and the issuer of the token behind it. A table names at least one key or an identity, unless `verify = false`. |
| `required` | boolean | `true` | `false` turns a missing signature into a note and lets the pull go on; a signature that is there but does not verify still fails it. |
| `rekor` | boolean | `true` | `false` trusts the key or certificate alone, without the transparency log entry (a private deployment that keeps no log). A bundle still has to carry a log entry or a timestamp, which cosign always adds. |
| `trusted_root` | absolute path | the public Sigstore root the binary embeds | The `trusted_root.json` of another Sigstore deployment. |

The keys are read by the service when a pull needs them, and checked when it
starts: a key or a trusted root it cannot read is reported in its journal and
fails the pulls of that registry. What the command line was given with
`--registry` chooses the registry, never the policy.

The file is read by the service, so a change takes effect on its next start:
`sudo systemctl restart nspawn.service` (or simply waiting for it to go idle)
picks it up. `--config` on the command line does not reach it: the command line
is a client and only carries the registry and its CA certificate. To put the
service on another file, name it when installing the service,
`sudo nspawn --config /etc/nspawn/lab.toml daemon --install`; the unit then
carries it, and so do the hooks the service writes for every machine.

## Environment variables

| Variable | Same as |
| --- | --- |
| `NSPAWN_REGISTRY` | `--registry` |
| `NSPAWN_CA_CERT` | `--ca-cert` |
| `NSPAWN_CONFIG` | `--config` |

They are convenient for scripts and for the end-to-end tests, which run against
a private registry with a private CA:

```shell
NSPAWN_REGISTRY=hub.nspawn.test:8443 NSPAWN_CA_CERT=/etc/zot/ca.crt nspawn hub ls
```

## Credentials

`nspawn login` keeps registry credentials in `/etc/nspawn/auth.json`, and that
file is the only one consulted. See
[Registries and credentials](/docs/images/#registries-and-credentials).

## Per-machine choices

Some settings belong to a machine rather than to the host, and are given when
it is created or started; every one of them is remembered until it is changed:

- `--backend` and `--mode` on `pull` and `build`; `--backend` on `create`.
- `--name` on `pull` and `build`, to choose the local name.
- `--network` (`bridge`, `veth`, `host`, `none` or networks made with
  `network create`, several of them), `--network-alias`, `-p`, `-e`, `-v`,
  `--label`, `--entrypoint` and the arguments after `--` on `start`, `run` and
  `create`. `-p none`, `-e none`, `-v none`, `--label none`,
  `--network-alias none` and `--image-command` forget what was remembered.
- `--restart`, `-m`/`--memory`, `--memory-swap`, `--cpus` and `--pids-limit` on `start`, `run`
  and `create`, applied at the next start, and on `update`, applied at once.
  `--restart no` and a limit of `0` remove them.
- The healthcheck (`--health-cmd` and the other `--health-*` flags,
  `--no-healthcheck`) on `start`, `run`, `create` and `update`, which changes
  it on a running machine at once.
- `--hostname`, `-u`, `-w`, `--cap-add`, `--cap-drop`, `--privileged`,
  `--read-only`, `--tmpfs`, `--shm-size`, `--device`, `--dns`, `--dns-search`,
  `--add-host`, `--ulimit`, `--oom-score-adj`, `--stop-signal`,
  `--stop-timeout`, `--timezone`, `--init`, `--sysctl` and `--secret` on `start`, `run` and
  `create`, applied at the next start. A list takes `none` to forget it, a
  value an empty string or `0`, and `--privileged=false` and
  `--read-only=false` take those back.
- `--rm` on `run`: the machine is removed when that run ends.
