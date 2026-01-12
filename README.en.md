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

Note: kernel headers for the running kernel must be installed
(`linux-headers-$KVER`).

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
- `out/<profile>/`  Build artifacts and logs
- `out/dist/`  Packages (tar.xz) per profile/KVER

## License

- Wrapper code (Makefile, profiles, docs): MIT, see `LICENSE`
- Patch files under `patches/`: GPL-2.0-only, see `LICENSES/GPL-2.0-only.txt`
