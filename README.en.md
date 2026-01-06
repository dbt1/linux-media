# linux-media-template

This repo is a slim wrapper around `tbsdtv/linux_media` to build only the
modules needed for specific tuners (without a full media_build stack).

Status: base profile `tbs5580` (works on Debian 13 / kernel 6.12.57).

German version: `README.md`

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

Result:
- Modules are placed under `out/<profile>/`
- Package: `out/dist/tbs5580-k<KVER>.tar.xz` via `make package PROFILE=tbs5580`
- Instructions inside the package: `INSTALL.txt` (English)

## Important notes

- No installation to `/lib/modules` and no `make install`.
- Modules are kernel-specific and only valid for the exact same KVER.
- Secure Boot: unsigned modules must be allowed.

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
