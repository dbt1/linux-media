# linux-media-template

This repo is a slim wrapper around `tbsdtv/linux_media` to build only the
modules needed for specific tuners (without a full media_build stack).

Status: profiles `tbs5580`, `t230`, and `t210` (T210 v2.0, often 0572:c68a).

German version: `README.de.md`
Index: `README.md`

## Quick start (tbs5580)

Optional, if `linux_media` is missing:

```
make fetch PROFILE=tbs5580
```

Optional, if a fresh tree needs patches:

```
make apply-patches PROFILE=tbs5580
```

Build (kernel detected via `uname -r`):

```
make tbs5580
```

Or:

```
make t210
```

Result:
- Modules are placed under `out/<profile>/`
- Package: `out/dist/tbs5580-k<KVER>.tar.xz` via `make package PROFILE=tbs5580`
- Instructions inside the package: `INSTALL.txt` (English)

Self-check across all profiles (no root, no hardware needed; builds every
profile once when kernel headers are available):

```
make check
```

Among other things it verifies that `dkms.conf` matches the profile, that the
snapshot is free of build artifacts, that the patch series really landed, and
that the generated tree builds under exactly the command line DKMS uses.

Optional precheck for a device (no build):

```
make precheck PROFILE=t230
```

The check tries to detect whether the device is already handled by the kernel
and reports possible blacklists (modprobe.d, kernel parameters).

## Important notes

- The tarball route (`make package`) installs nothing to `/lib/modules`.
  The DKMS route deliberately does -- see *Automating the rebuild (DKMS)*.
- Modules are kernel-specific and only valid for the exact same KVER.
  That is exactly what the DKMS route is for.
- Secure Boot: the tarball route produces unsigned modules, which have to be
  allowed. The DKMS route signs with a key it generates itself
  (`/var/lib/dkms/mok.key`); there you need the MOK enrolment instead:
  `sudo mokutil --import /var/lib/dkms/mok.pub`.

## Kernel update (rebuild, tarball fallback only)

**With DKMS this section is moot** -- see *Automating the rebuild (DKMS)*
below. It only applies to hosts using the `out/` tarball route, where
`tbs5580-modules.service` is active. On a DKMS host the service is disabled
and would report the vermagic error again after a kernel update.

On such a host you must rebuild the modules by hand after a kernel update.

```
KVER=$(uname -r)
make package PROFILE=tbs5580 KVER=$KVER
make package PROFILE=t230  KVER=$KVER
make package PROFILE=t210  KVER=$KVER
```

For `tbs5580` there is also a short helper script in the repo:

```
./scripts/tbs5580/rebuild.sh
sudo systemctl restart tbs5580-modules.service
```

Note: kernel headers for the running kernel must be installed
(`linux-headers-$KVER`).

## Symptoms of a missing rebuild

After a kernel update without a rebuild:

- `/dev/dvb` is missing entirely, Neutrino starts without a tuner
- `systemctl status tbs5580-modules.service` -> `failed`, ExecStart exit 1
- `load-tbs5580.sh` aborts in `check_vermagic`: `vermagic mismatch for <KVER>`
- `lsmod` shows only `dvb_core` (maybe `si2157`), no `dvb_usb_tbs5580`
- `modinfo -F vermagic out/<profile>/*.ko` != `uname -r`

This is not a driver defect: the loader deliberately refuses to load incompatible
modules. The fix is the rebuild above, not `rmmod`/`modprobe`.

## Automating the rebuild (DKMS)

Implemented (as of 2026-08-23). DKMS rebuilds the modules for every kernel
update, including unattended apt upgrades -- as long as the sources still build
against the new kernel API. An API break (a jump to a new Debian release, say)
needs updated sources like any out-of-tree driver; DKMS then fails silently and
the tuner is missing. `modprobe` and udev then load them
on their own -- `tbs5580-modules.service` and `load-tbs5580.sh` are no longer
needed.

### Prerequisite: headers meta package

```
sudo apt install linux-headers-amd64
```

Without it new kernels arrive automatically (`linux-image-amd64`) but their
headers do not, and DKMS fails silently. This is the most common reason for the
tuner still being gone after an update.

### Setup

The recommended route is the package from the next section: it copies the
sources to /usr/src/ itself and registers them with DKMS.

By hand works too, but the tree has to end up in /usr/src/ as well:
`dkms add -m <name> -v <version>` looks there and nowhere else, so a tree
under `out/` is not found.

```
make dkms-source PROFILE=tbs5580
sudo cp -a out/dkms/linux-media-tbs5580-$(cat VERSION) /usr/src/
sudo dkms add     -m linux-media-tbs5580 -v $(cat VERSION)
sudo dkms install -m linux-media-tbs5580 -v $(cat VERSION)
```

Do not use `dkms add out/dkms/<tree>`: that records a symlink to exactly this
directory, and the next `make dkms-source` deletes it -- the autobuild on the
next kernel update would then fail.

`make dkms-source` writes a self-contained source tree to
`out/dkms/<package>-<version>/`: `dkms.conf`, a wrapper Makefile, the shared
`mk/build-modules.mk` and the driver sources needed (only the files of the
directories named in the profile, about 9 MB). All paths and module names come
from `profiles/<name>.mk`, so the target is not tied to `tbs5580`.

The snapshot is taken with `git archive` straight from the pinned
`LINUX_MEDIA_REF`, and the profile's patch series is then applied to it. The
working tree under `linux_media/` plays no part: neither build artifacts nor
another profile's patches can end up in the package, and the result is the
same on every host. `PROVENANCE` records the commit, the series and how to
reproduce it.

### Shipping it

```
sudo apt install debhelper dh-dkms
make dkms-deb PROFILE=tbs5580
```

Result: `out/dist/linux-media-tbs5580-dkms_<version>_all.deb`. The package
depends hard on `dkms` and on a headers meta package
(`linux-headers-amd64 | linux-headers-arm64 | linux-headers-generic`), so the
target machine cannot end up in the same broken state. Special kernels (HWE,
cloud, lowlatency, self-built) do not necessarily get their headers through one
of these meta packages; there they have to be matched by hand.

Maintainer field and version can be set at build time:

```
make dkms-deb PROFILE=tbs5580 DEB_MAINTAINER='Name <mail@example.org>'
```

Without it the hostname is used. The package is reproducible: the changelog
date comes from `SOURCE_DATE_EPOCH` or the last commit, not from the clock. The tuner firmware is proprietary and must not
be shipped, so it is not included; the `postinst` warns when it is missing,
details in `README.Debian`.

The Debian templates live in `packaging/debian/` and are filled in at build
time with profile, version, maintainer and firmware list.

### Migrating from the tarball route

If you used `tbs5580-modules.service` before, switch it off -- otherwise it
loads the old modules from `out/` on the next boot and shadows the ones DKMS
installed:

```
sudo systemctl disable --now tbs5580-modules.service
```

Neither the package nor a make target does this for you; it changes the system
and stays a manual step.

### What it costs

DKMS installs into `/lib/modules/<KVER>/updates/dkms/`. This deliberately gives
up the original "no installation into `/lib/modules`" principle. `updates/dkms`
ranks above `kernel/`, so the modules override in-tree modules of the same name
for *all* devices that use them. For `tbs5580` that is `dvb-usb` alone
(`si2183` and `av201x` do not exist in-tree). For `t230`/`t210` it is all
four: `dvb_usb_v2`, `dvb-usb-dvbsky`, `si2168` and `si2157`. Check this first
on a host with other DVB hardware; the generated `README.Debian` lists the
names per profile.

The `out/` tarball route (`make package`) stays unchanged as a fallback for
hosts without DKMS.

### Rejected alternative

A kernel postinst hook (`/etc/kernel/postinst.d/`) would have kept the `out/`
principle, but it has to drop from root into the user context, fails silently
without headers, and is useless for shipping. Hence DKMS.

## Add a new tuner profile

1. Create `profiles/<name>.mk`
2. If needed, add patches under `patches/<name>/` and maintain `series`
3. Define modules and Kconfig flags in the profile

Example profile variables:
- `USB_MODULES`, `FE_MODULES`, `TUNER_MODULES`
- `USB_KCONFIG`, `FE_KCONFIG`, `TUNER_KCONFIG`
- `PROFILE_CFLAGS`
- `LINUX_MEDIA_URL`, `LINUX_MEDIA_REF`

## Directory layout

- `profiles/`  Profiles per tuner
- `patches/`   Patch series per tuner
- `mk/`        Shared make fragments (`build-modules.mk`)
- `scripts/common/check.sh`  Self-check, invoked by `make check`
- `packaging/debian/`  Templates for the DKMS `.deb`
- `scripts/`  Version-controlled helpers, e.g. `scripts/tbs5580/rebuild.sh`
- `VERSION`    Version of the DKMS package
- `out/<profile>/`  Generated build artifacts, loaders, and logs
- `out/dkms/`  Generated DKMS source trees per profile/version
- `out/dist/`  Packages (tar.xz per profile/KVER, `.deb` per profile/version)

Details for helper-script placement live in `scripts/README.md`.

## License

- Wrapper code (Makefile, profiles, docs): MIT, see `LICENSE`
- Patch files under `patches/`: GPL-2.0-only, see `LICENSES/GPL-2.0-only.txt`
