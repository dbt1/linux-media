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

Optional precheck (no build):

```
make precheck PROFILE=t230
```

The check tries to detect whether the device is already handled by the kernel
and reports possible blacklists (modprobe.d, kernel parameters).

## Important notes

- No installation to `/lib/modules` and no `make install`.
- Modules are kernel-specific and only valid for the exact same KVER.
- Secure Boot: unsigned modules must be allowed.

## Kernel update (rebuild)

After a kernel update you must rebuild the modules.

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

## Automating the rebuild (proposals, not implemented yet)

Status: open (as of 2026-07-12). The rebuild is manual today. Consequence: the
tuner is gone after every kernel update until someone rebuilds it by hand.

### Prerequisite for both options: headers meta package

`linux-image-amd64` is installed, `linux-headers-amd64` is not. New kernels
therefore arrive automatically, the matching headers do not. After an update a
rebuild is not even possible until the headers are installed.

```
sudo apt install linux-headers-amd64
```

This is worthwhile independently of option A/B and is a prerequisite for both.

### Option A: DKMS (robust)

The kernel update builds the modules automatically, including unattended apt
upgrades, and allows module signing for Secure Boot.

- Needs a `dkms.conf` per profile and the sources under `/usr/src/<name>-<ver>`
- Breaks the repo principle "no installation to `/lib/modules`"
- `tbs5580-modules.service` and `load-tbs5580.sh` would become obsolete (`modprobe` suffices)

### Option B: kernel postinst hook (lightweight)

Keeps the repo principle (modules stay in `out/`) and only calls the existing
rebuild. Sketch `/etc/kernel/postinst.d/zz-linux-media`:

```
#!/bin/sh
set -e
KVER="$1"
[ -n "$KVER" ] || exit 0
[ -d "/lib/modules/$KVER/build" ] || exit 0
su - tg -c "KVER=$KVER /home/tg/sources/linux-media/scripts/tbs5580/rebuild.sh"
```

- Runs as root and must switch to the user context for the build
- Fails silently when the headers are missing (see prerequisite above)
- No module signing, Secure Boot stays manual

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
- `scripts/`  Version-controlled helpers, e.g. `scripts/tbs5580/rebuild.sh`
- `out/<profile>/`  Generated build artifacts, loaders, and logs
- `out/dist/`  Packages (tar.xz) per profile/KVER

Details for helper-script placement live in `scripts/README.md`.

## License

- Wrapper code (Makefile, profiles, docs): MIT, see `LICENSE`
- Patch files under `patches/`: GPL-2.0-only, see `LICENSES/GPL-2.0-only.txt`
