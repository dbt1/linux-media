# linux-media-template

English version: `README.en.md`

Dieses Repo ist ein schlanker Wrapper um `tbsdtv/linux_media`, um gezielt
Module fuer einzelne Tuner zu bauen (ohne kompletten media_build Stack).

Status: Profile `tbs5580` und `t230` (MyGica T230C v2, 0572:c68a).

## Schnellstart (tbs5580)

Optional, wenn `linux_media` noch fehlt:

```
make fetch PROFILE=tbs5580
```

Optional, wenn ein frischer Tree gepatcht werden soll:

```
make apply-patches PROFILE=tbs5580
```

Build (Kernel automatisch per `uname -r`):

```
make tbs5580
```

Ergebnis:
- Module liegen unter `out/<profil>/`
- Paket: `out/dist/tbs5580-k<KVER>.tar.xz` via `make package PROFILE=tbs5580`
- Anleitung im Paket: `INSTALL.txt` (English)

Optionaler Vorab-Check (kein Build):

```
make precheck PROFILE=t230
```

Der Check versucht zu erkennen, ob das Geraet bereits vom Kernel genutzt wird
und meldet moegliche Blacklists (modprobe.d, Kernel-Parameter).

## Wichtige Hinweise

- Keine Installation nach `/lib/modules` und kein `make install`.
- Module sind kernel-spezifisch und gelten nur fuer den exakt gleichen KVER.
- Secure Boot: Unsigned Modules muessen erlaubt sein.

## Ein neues Tuner-Profil hinzufuegen

1. `profiles/<name>.mk` anlegen
2. Falls noetig, Patches unter `patches/<name>/` ablegen und `series` pflegen
3. Im Profil Module und Kconfig-Flags definieren

Beispiel-Variablen im Profil:
- `USB_MODULES`, `FE_MODULES`, `TUNER_MODULES`
- `USB_KCONFIG`, `FE_KCONFIG`, `TUNER_KCONFIG`
- `PROFILE_CFLAGS`
- `LINUX_MEDIA_URL`, `LINUX_MEDIA_REF`

## Verzeichnisstruktur

- `profiles/`  Profile pro Tuner
- `patches/`   Patch-Serien pro Tuner
- `out/<profil>/`  Build-Artefakte und Logs
- `out/dist/`  Pakete (tar.xz) pro Profil/KVER
