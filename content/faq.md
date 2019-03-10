---
title: "FAQ"
date: 2019-03-10T23:51:12+01:00
draft: false
---

**What is nspawn.org?**

The website `nspawn.org` is a hub for `systemd-nspawn` containers.

**Do I need systemd for nspawn.org**

Yes.

**Ok, cool. How does nspawn.org work?**

You have two options. The easy way via our wrapper `nspawn` or the manually way via the `machinectl` command.
If you want to use the wrapper `nspawn` you can find it here: [https://github.com/nspawn/nspawn](https://github.com/nspawn/nspawn)

If you want to do it manually, here is a short tutorial:
First you need to set up your `/etc/systemd/import-pubring.gpg` keyring file. You can do this via the following command:

`sudo gpg --no-default-keyring --keyring=/etc/systemd/import-pubring.gpg --fingerprint`

Second you need to import our master key. The master key has the following key id:

[575D E887 94A4 5D84 456D  8897 A232 A512 E7D0 BA83](https://nspawn.org/storage/masterkey.pgp)

You can either download it manually and import it into your keyring or you search it directly via GPG:

`sudo gpg --no-default-keyring --keyring=/etc/systemd/import-pubring.gpg --search 575DE88794A45D84456D8897A232A512E7D0BA83`

Don't forget to trust our master key, after importing it! If everything is set up, you can go and download your first image.
You can find a full list of all images here: [https://nspawn.org/storage/list.txt](https://nspawn.org/storage/list.txt)

Use `machinectl pull-tar` or `machinectl pull-raw` to download the right image (depending on the image type):

`machinectl pull-<tar|raw> https://nspawn.org/storage/<distribution>/<release>/<type>/image.<type>.xz`

For example:

`machinectl pull-tar https://nspawn.org/storage/fedora/29/tar/image.tar.xz`

Now you can operate on the imported image as usually via `machinectl start <image name>`, `machinectl login <image-name>`, `machinectl shell <image-name>`, etc.

We recommend the use of our `nspawn` wrapper script.
