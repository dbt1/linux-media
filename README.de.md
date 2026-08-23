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

- Der Tarball-Weg (`make package`) installiert nichts nach `/lib/modules`.
  Der DKMS-Weg tut es bewusst -- siehe *Rebuild automatisieren (DKMS)*.
- Module sind kernel-spezifisch und gelten nur fuer den exakt gleichen KVER.
  Genau deshalb gibt es den DKMS-Weg.
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

## Rebuild automatisieren (DKMS)

Umgesetzt (Stand 2026-08-23). DKMS baut die Module bei jedem Kernel-Update
automatisch mit, auch bei unbeaufsichtigten apt-Upgrades. `modprobe` und udev
laden sie dann selbst -- `tbs5580-modules.service` und `load-tbs5580.sh` werden
nicht mehr gebraucht.

### Voraussetzung: Header-Metapaket

```
sudo apt install linux-headers-amd64
```

Ohne das kommen neue Kernel automatisch (`linux-image-amd64`), die passenden
Header aber nicht -- und DKMS scheitert dann still. Das ist die haeufigste
Ursache dafuer, dass der Tuner nach einem Update trotzdem weg ist.

### Einrichten

```
make dkms-source PROFILE=tbs5580
sudo dkms add     -m linux-media-tbs5580 -v $(cat VERSION)
sudo dkms install -m linux-media-tbs5580 -v $(cat VERSION)
```

`make dkms-source` erzeugt unter `out/dkms/<paket>-<version>/` einen
eigenstaendigen Quellbaum: `dkms.conf`, ein Wrapper-Makefile, die gemeinsame
`mk/build-modules.mk` und die noetigen Treiberquellen (nur die Dateien der im
Profil genannten Verzeichnisse, ca. 9 MB). Alle Pfade und Modulnamen kommen aus
`profiles/<name>.mk`, das Target ist also nicht auf `tbs5580` festgelegt.

Der Snapshot wird nur erzeugt, wenn `linux_media` sauber ist, auf einem
Nachfahren von `LINUX_MEDIA_REF` steht und die Patch-Serie des Profils
tatsaechlich angewendet ist. Sonst bricht das Target ab -- ein nicht
reproduzierbarer Baum soll nicht ins Paket wandern. Was genau drin ist, steht
in `PROVENANCE`.

### Ausliefern

```
sudo apt install debhelper dh-dkms
make dkms-deb PROFILE=tbs5580
```

Ergebnis: `out/dist/linux-media-tbs5580-dkms_<version>_all.deb`. Das Paket
haengt hart an `dkms` und an einem Header-Metapaket
(`linux-headers-amd64 | linux-headers-generic`), damit auf dem Zielrechner
nicht derselbe Zustand entsteht. Die Tuner-Firmware ist proprietaer und darf
nicht mitgeliefert werden; das `postinst` warnt bei Abwesenheit, Details in
`README.Debian`.

Die Debian-Vorlagen liegen unter `packaging/debian/` und werden beim Bauen mit
Profil, Version, Maintainer und Firmwareliste gefuellt.

### Was das kostet

DKMS installiert nach `/lib/modules/<KVER>/updates/dkms/`. Das gibt das
urspruengliche Prinzip "keine Installation nach `/lib/modules`" bewusst auf.
`updates/dkms` rangiert vor `kernel/`, die Module ueberschreiben also
gleichnamige In-Tree-Module fuer *alle* Geraete, die sie nutzen -- bei
`tbs5580` betrifft das `dvb-usb`, bei `t230`/`t210` zusaetzlich `si2168` und
`si2157`. Auf einem Host mit weiterer DVB-Hardware vorher pruefen.

Der `out/`-Tarball-Weg (`make package`) bleibt unveraendert als Fallback fuer
Hosts ohne DKMS.

### Verworfene Alternative

Ein Kernel-Postinst-Hook (`/etc/kernel/postinst.d/`) haette das `out/`-Prinzip
behalten, muesste aber aus root in den User-Kontext wechseln, scheitert ohne
Header still und taugt nicht zum Ausliefern. Deshalb DKMS.

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
- `mk/`        Gemeinsame Make-Fragmente (`build-modules.mk`)
- `packaging/debian/`  Vorlagen fuer das DKMS-`.deb`
- `scripts/`   Versionierte Helfer, z. B. `scripts/tbs5580/rebuild.sh`
- `VERSION`    Version des DKMS-Pakets
- `out/<profil>/`  Generierte Build-Artefakte, Loader und Logs
- `out/dkms/`  Generierte DKMS-Quellbaeume pro Profil/Version
- `out/dist/`  Pakete (tar.xz pro Profil/KVER, `.deb` pro Profil/Version)

Details zur Ablage von Hilfsskripten stehen in `scripts/README.md`.

## Lizenz

- Wrapper-Code (Makefile, Profile, Docs): MIT, siehe `LICENSE`
- Patch-Dateien unter `patches/`: GPL-2.0-only, siehe `LICENSES/GPL-2.0-only.txt`
