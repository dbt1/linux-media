# linux-media-template

English version: `README.en.md`
Uebersicht: `README.md`

Dieses Repo ist ein schlanker Wrapper um `tbsdtv/linux_media`, um gezielt
Module fuer einzelne Tuner zu bauen (ohne kompletten media_build Stack).

Status: Profile `tbs5580`, `t230` und `t210` (T210 v2.0, ggf. 0572:c68a).

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

Oder:

```
make t210
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

## Kernel-Update (Rebuild)

Nach einem Kernel-Update muessen die Module neu gebaut werden.

```
KVER=$(uname -r)
make package PROFILE=tbs5580 KVER=$KVER
make package PROFILE=t230  KVER=$KVER
make package PROFILE=t210  KVER=$KVER
```

Fuer `tbs5580` gibt es auch einen kurzen Helfer im Repo:

```
./scripts/tbs5580/rebuild.sh
sudo systemctl restart tbs5580-modules.service
```

Hinweis: Kernel-Header muessen zum laufenden Kernel installiert sein
(`linux-headers-$KVER`).

## Symptome eines fehlenden Rebuilds

Nach einem Kernel-Update ohne Rebuild:

- `/dev/dvb` fehlt komplett, Neutrino startet ohne Tuner
- `systemctl status tbs5580-modules.service` -> `failed`, ExecStart Exit 1
- `load-tbs5580.sh` bricht in `check_vermagic` ab: `vermagic mismatch for <KVER>`
- `lsmod` zeigt nur `dvb_core` (ggf. `si2157`), kein `dvb_usb_tbs5580`
- `modinfo -F vermagic out/<profil>/*.ko` != `uname -r`

Das ist kein Treiberdefekt: Der Loader verweigert bewusst das Laden inkompatibler
Module. Der Fix ist der Rebuild oben, nicht `rmmod`/`modprobe`.

## Rebuild automatisieren (Vorschlaege, noch nicht umgesetzt)

Status: offen (Stand 2026-07-12). Der Rebuild ist heute manuell. Folge: Der Tuner
ist nach jedem Kernel-Update weg, bis jemand ihn von Hand neu baut.

### Voraussetzung fuer beide Optionen: Header-Metapaket

`linux-image-amd64` ist installiert, `linux-headers-amd64` nicht. Neue Kernel
kommen also automatisch, die passenden Header nicht. Damit ist nach einem Update
nicht einmal ein Rebuild moeglich, bis die Header nachinstalliert sind.

```
sudo apt install linux-headers-amd64
```

Das ist unabhaengig von Option A/B sinnvoll und Voraussetzung fuer beide.

### Option A: DKMS (robust)

Das Kernel-Update baut die Module automatisch mit, auch bei unbeaufsichtigten
apt-Upgrades, und erlaubt Modulsignatur fuer Secure Boot.

- Braucht ein `dkms.conf` je Profil und die Sourcen unter `/usr/src/<name>-<ver>`
- Bricht mit dem Repo-Prinzip "keine Installation nach `/lib/modules`"
- `tbs5580-modules.service` und `load-tbs5580.sh` wuerden entfallen (`modprobe` genuegt)

### Option B: Kernel-Postinst-Hook (leichtgewichtig)

Behaelt das Repo-Prinzip (Module bleiben in `out/`) und ruft nur den vorhandenen
Rebuild auf. Skizze `/etc/kernel/postinst.d/zz-linux-media`:

```
#!/bin/sh
set -e
KVER="$1"
[ -n "$KVER" ] || exit 0
[ -d "/lib/modules/$KVER/build" ] || exit 0
su - tg -c "KVER=$KVER /home/tg/sources/linux-media/scripts/tbs5580/rebuild.sh"
```

- Laeuft als root und muss fuer den Build in den User-Kontext wechseln
- Schlaegt still fehl, wenn die Header fehlen (siehe Voraussetzung oben)
- Keine Modulsignatur, Secure Boot bleibt Handarbeit

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
- `scripts/`   Versionierte Helfer, z. B. `scripts/tbs5580/rebuild.sh`
- `out/<profil>/`  Generierte Build-Artefakte, Loader und Logs
- `out/dist/`  Pakete (tar.xz) pro Profil/KVER

Details zur Ablage von Hilfsskripten stehen in `scripts/README.md`.

## Lizenz

- Wrapper-Code (Makefile, Profile, Docs): MIT, siehe `LICENSE`
- Patch-Dateien unter `patches/`: GPL-2.0-only, siehe `LICENSES/GPL-2.0-only.txt`
