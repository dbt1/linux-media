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

Selbsttest ueber alle Profile (kein root, keine Hardware noetig; baut jedes
Profil einmal, wenn Kernel-Header da sind):

```
make check
```

Er prueft unter anderem, ob `dkms.conf` zum Profil passt, ob der Snapshot frei
von Build-Artefakten ist, ob die Patch-Serie wirklich angekommen ist und ob der
generierte Baum unter genau der Kommandozeile baut, die DKMS verwendet.

Optionaler Vorab-Check fuer ein Geraet (kein Build):

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
- Secure Boot: Der Tarball-Weg liefert unsignierte Module, die erlaubt sein
  muessen. Der DKMS-Weg signiert dagegen mit einem selbst erzeugten Schluessel
  (`/var/lib/dkms/mok.key`); dort ist statt dessen das MOK-Enrolment noetig:
  `sudo mokutil --import /var/lib/dkms/mok.pub`.

## Kernel-Update (Rebuild, nur Tarball-Fallback)

**Mit DKMS ist dieser Abschnitt gegenstandslos** -- siehe *Rebuild
automatisieren (DKMS)* weiter unten. Er gilt nur noch fuer Hosts, die den
`out/`-Tarball-Weg benutzen; dort muessen die Module nach einem Kernel-Update
von Hand neu gebaut und neu geladen werden.

```
KVER=$(uname -r)
make package PROFILE=tbs5580 KVER=$KVER
make package PROFILE=t230  KVER=$KVER
make package PROFILE=t210  KVER=$KVER
```

Fuer `tbs5580` gibt es auch einen kurzen Helfer im Repo:

```
./scripts/tbs5580/rebuild.sh
```

Die Lade- und Entlade-Kommandos zum jeweiligen Build stehen in der
mitgenerierten `out/<profil>/INSTALL.txt`. Wer noch die Systemd-Unit einer
aelteren Fassung dieses Repos benutzt, startet statt dessen sie neu.

Hinweis: Kernel-Header muessen zum laufenden Kernel installiert sein
(`linux-headers-$KVER`).

## Symptome eines fehlenden Rebuilds

Nach einem Kernel-Update ohne Rebuild:

- `/dev/dvb` fehlt komplett, Neutrino startet ohne Tuner
- `lsmod` zeigt nur `dvb_core` (ggf. `si2157`), kein `dvb_usb_tbs5580`
- `modinfo -F vermagic out/<profil>/*.ko` != `uname -r`

Auf Hosts, die noch nach der alten Anleitung eingerichtet sind, zusaetzlich:
`systemctl status tbs5580-modules.service` -> `failed` mit ExecStart Exit 1,
und `load-tbs5580.sh` bricht in `check_vermagic` ab (`vermagic mismatch for
<KVER>`). Unit und Loader stammen aus einer aelteren Fassung dieses Repos und
werden hier nicht mehr erzeugt.

Das ist kein Treiberdefekt: Der Loader verweigert bewusst das Laden inkompatibler
Module. Der Fix ist der Rebuild oben, nicht `rmmod`/`modprobe`.

## Rebuild automatisieren (DKMS)

Umgesetzt (Stand 2026-08-23). DKMS baut die Module bei jedem Kernel-Update
automatisch mit, auch bei unbeaufsichtigten apt-Upgrades -- solange die Quellen
gegen die neue Kernel-API bauen. Ein API-Bruch (etwa bei einem Sprung auf eine
neue Debian-Version) braucht wie bei jedem Out-of-Tree-Treiber nachgezogene
Quellen; DKMS scheitert dann still und der Tuner fehlt. `modprobe` und udev
laden die Module selbst -- die Systemd-Unit und das Loader-Skript aelterer
Fassungen dieses Repos werden nicht mehr gebraucht und nicht mehr erzeugt.

### Voraussetzung: Header-Metapaket

```
sudo apt install linux-headers-amd64
```

Ohne das kommen neue Kernel automatisch (`linux-image-amd64`), die passenden
Header aber nicht -- und DKMS scheitert dann still. Das ist die haeufigste
Ursache dafuer, dass der Tuner nach einem Update trotzdem weg ist.

### Einrichten

Der empfohlene Weg ist das Paket aus dem naechsten Abschnitt -- es kopiert die
Quellen selbst nach `/usr/src/` und meldet sie bei DKMS an.

Von Hand geht es auch, dann muss der Baum aber ebenfalls nach `/usr/src/`:
`dkms add -m <name> -v <version>` sucht ausschliesslich dort und findet einen
Baum unter `out/` nicht.

```
make dkms-source PROFILE=tbs5580
sudo cp -a out/dkms/linux-media-tbs5580-$(cat VERSION) /usr/src/
sudo dkms add     -m linux-media-tbs5580 -v $(cat VERSION)
sudo dkms install -m linux-media-tbs5580 -v $(cat VERSION)
```

Nicht `dkms add out/dkms/<baum>` benutzen: das legt einen Symlink auf genau
dieses Verzeichnis an, und der naechste `make dkms-source` loescht es -- der
Autobuild beim naechsten Kernel-Update wuerde dann fehlschlagen.

`make dkms-source` erzeugt unter `out/dkms/<paket>-<version>/` einen
eigenstaendigen Quellbaum: `dkms.conf`, ein Wrapper-Makefile, die gemeinsame
`mk/build-modules.mk` und die noetigen Treiberquellen (nur die Dateien der im
Profil genannten Verzeichnisse, ca. 9 MB). Alle Pfade und Modulnamen kommen aus
`profiles/<name>.mk`, das Target ist also nicht auf `tbs5580` festgelegt.

Der Snapshot kommt per `git archive` direkt aus dem gepinnten
`LINUX_MEDIA_REF`, danach wird die Patch-Serie des Profils darauf angewendet.
Der Arbeitsbaum unter `linux_media/` spielt dabei keine Rolle: es landen weder
Build-Artefakte noch Patches eines anderen Profils im Paket, und das Ergebnis
ist auf jedem Host identisch. `PROVENANCE` nennt Commit, Serie und den Befehl
zum Nachbauen.

### Ausliefern

```
sudo apt install debhelper dh-dkms
make dkms-deb PROFILE=tbs5580
```

Ergebnis: `out/dist/linux-media-tbs5580-dkms_<version>_all.deb`. Das Paket
haengt hart an `dkms` und an einem Header-Metapaket
(`linux-headers-amd64 | linux-headers-arm64 | linux-headers-generic`), damit
auf dem Zielrechner nicht derselbe Zustand entsteht. Sonderkernel (HWE, cloud,
lowlatency, selbstgebaut) bringen ihre Header nicht zwingend ueber eines
dieser Metapakete mit -- dort muessen sie von Hand passen.

Maintainer-Feld und Version lassen sich beim Bauen setzen:

```
make dkms-deb PROFILE=tbs5580 DEB_MAINTAINER='Name <mail@example.org>'
```

Ohne Angabe steht `linux-media packaging <linux-media@invalid>` im Paket --
bewusst eine feste, nicht aufloesbare Adresse und nicht der Hostname, damit
zwei Rechner aus derselben Quelle dasselbe Paket bauen. Das Paket ist
reproduzierbar: das Changelog-Datum stammt aus `SOURCE_DATE_EPOCH` bzw. dem
letzten Commit und wird in UTC formatiert, nicht aus der Uhr und nicht aus der
Zeitzone. Ohne Git-Kontext und ohne `SOURCE_DATE_EPOCH` bricht `dkms-deb` ab,
statt heimlich die Uhr zu nehmen. Firmware liefert das Paket keine mit; das
`postinst` warnt bei Abwesenheit, Herkunft je Tuner in `README.Debian`.

Die Debian-Vorlagen liegen unter `packaging/debian/` und werden beim Bauen mit
Profil, Version, Maintainer und Firmwareliste gefuellt.

### Umstieg von der Tarball-Variante

Wer vorher `tbs5580-modules.service` benutzt hat, sollte ihn abschalten -- sonst
laedt er beim naechsten Boot die alten Module aus `out/` und beschattet die von
DKMS installierten:

```
sudo systemctl disable --now tbs5580-modules.service
```

Weder das Paket noch ein Make-Ziel tut das automatisch; es ist ein Eingriff ins
System und bleibt Handarbeit.

### Was das kostet

DKMS installiert nach `/lib/modules/<KVER>/updates/dkms/`. Das gibt das
urspruengliche Prinzip "keine Installation nach `/lib/modules`" bewusst auf.

Existiert ein gleichnamiges In-Tree-Modul, laesst DKMS es nicht einfach in der
Suchreihenfolge hinter sich: es *verschiebt* die Originaldatei nach
`/var/lib/dkms/<paket>/original_module/` und setzt den eigenen Build an ihre
Stelle (`dkms status` meldet dann "Original modules exist"). Das
out-of-tree-Modul bedient danach *alle* Geraete, die es nutzen, nicht nur
diesen Tuner; beim Entfernen des Pakets legt DKMS das Original zurueck.
Geht der DKMS-Zustand verloren, ist das Original weg -- an `dvb-usb`
haengen rund 25 In-Tree-Treiber.

Bei `tbs5580` betrifft das nur `dvb-usb` (`si2183` und `av201x` gibt es in-tree
nicht). Bei `t230`/`t210` sind es alle vier: `dvb_usb_v2`, `dvb-usb-dvbsky`,
`si2168` und `si2157`. Auf einem Host mit weiterer DVB-Hardware vorher
pruefen; die generierte `README.Debian` nennt die mitgelieferten Module je
Profil -- welche davon tatsaechlich etwas verdraengen, haengt vom Kernel ab.

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
- `scripts/common/check.sh`  Selbsttest, aufgerufen von `make check`
- `packaging/debian/`  Vorlagen fuer das DKMS-`.deb`
- `scripts/`   Versionierte Helfer, z. B. `scripts/tbs5580/rebuild.sh`
- `VERSION`    Version des DKMS-Pakets
- `out/<profil>/`  Generierte Build-Artefakte und Logs
- `out/dkms/`  Generierte DKMS-Quellbaeume pro Profil/Version
- `out/dist/`  Pakete (tar.xz pro Profil/KVER, `.deb` pro Profil/Version)

Details zur Ablage von Hilfsskripten stehen in `scripts/README.md`.

## Lizenz

- Wrapper-Code (Makefile, Profile, Docs): MIT, siehe `LICENSE`
- Patch-Dateien unter `patches/`: GPL-2.0-only, siehe `LICENSES/GPL-2.0-only.txt`
