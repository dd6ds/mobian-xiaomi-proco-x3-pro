# Mobian für das Xiaomi POCO X3 Pro (vayu)

🇬🇧 [English version](README.md)

Build-Skripte, Flash-Skript und ein GitHub-Actions-Workflow, die ein flashbares
[Mobian](https://mobian-project.org/)-Image (Debian fürs Telefon) für das
**Xiaomi POCO X3 Pro** (Codename `vayu`, auch `bhima`, Snapdragon 860 / SM8150) erzeugen.

> ⚠️ **Inoffiziell und experimentell.** Mobian unterstützt vayu nicht offiziell.
> Dieses Projekt nutzt Mobians eigenen Portierungsweg `qcom-wip` zusammen mit dem
> Mainline-SM8150-Kernel und der Firmware aus dem
> [postmarketOS-Port für vayu](https://wiki.postmarketos.org/wiki/Xiaomi_POCO_X3_Pro_(xiaomi-vayu)).
> Die Hardware-Unterstützung entspricht daher der von postmarketOS – insbesondere
> **das Modem (Telefonie / SMS / mobile Daten) funktioniert unter Mainline noch nicht zuverlässig**.
> **Das Flashen löscht alle Daten auf dem Telefon und entfernt Android.**

## Funktionsweise

```
┌──────────────────────────┐   ┌──────────────────────────┐   ┌──────────────────────────────┐
│ 1. Kernel (.deb)         │   │ 2. Gerätepakete (.deb)   │   │ 3. Image (debos)             │
│ sm8150-mainline v7.0.0   │──▶│ firmware-xiaomi-vayu     │──▶│ mobian-recipes, qcom-wip     │
│ + pmOS-Patches & Config  │   │ mobian-xiaomi-vayu-tweaks│   │ config/vayu.toml             │
│ make bindeb-pkg (clang)  │   │ (UCM-Audioprofil)        │   │ → boot-vayu-{huaxing,tianma} │
└──────────────────────────┘   └──────────────────────────┘   │ → rootfs.img (sparse)        │
                                                              └──────────────────────────────┘
```

| Pfad | Inhalt |
|---|---|
| `build.sh` | Ein Befehl für den kompletten Build (alles läuft in Docker) |
| `flash.sh` | Flasht das Ergebnis per fastboot (mit Panel-Erkennung) |
| `versions.env` | Gepinnte Versionen + Prüfsummen von Kernel, Firmware, mobian-recipes |
| `config/vayu.toml` | Mobian-Gerätekonfiguration (Boot-Image-Offsets, DTB-Namen, Panel-Varianten) |
| `kernel/` | postmarketOS-Kernelconfig, Patches, Mobian-Config-Fragment |
| `device/` | ALSA-UCM-Profil; Dateien in `device/rootfs/` (optional) landen im Image |
| `scripts/` | Einzelne Build-Schritte |
| `.github/workflows/build.yml` | Build in GitHub Actions per Klick |

### Display-Panel-Varianten

Das POCO X3 Pro wird mit einem von zwei Displays ausgeliefert, **Huaxing** oder
**Tianma**, die unterschiedliche Device-Trees brauchen. Jeder Build erzeugt deshalb zwei
Boot-Images: `*.boot-vayu-huaxing.img` und `*.boot-vayu-tianma.img`. Das Rootfs ist identisch.
Eine falsche Wahl ist harmlos: der Bildschirm bleibt schwarz – einfach das andere
Boot-Image flashen (`./flash.sh --boot-only --panel <anderes>`).

## Build mit GitHub Actions (per Klick)

1. Diesen Ordner in ein GitHub-Repository pushen.
2. **Actions → „Build Mobian image (POCO X3 Pro / vayu)“ → Run workflow** öffnen.
3. Optionen wählen:
   - **environment**: `phosh` (Standard), `plasma-mobile` oder `lomiri`
   - **username / password**: Standardbenutzer (Standard `mobian` / `1234`, steht im Log!)
   - **kernel_tag**: leer = gepinnte Version, sonst z. B. `v7.1.0-sm8150`
   - **recipes_ref**: leer = gepinnter mobian-recipes-Commit, z. B. `master`
   - **release**: Ergebnis als GitHub-Release veröffentlichen
4. Nach ca. 1–2 Stunden liegt das Image vor
   - als **Release** (Tag `vayu-<env>-<datum>-<lauf>`) und
   - als Workflow-**Artefakt** (7 Tage), dazu die `.deb`-Pakete (14 Tage).

**SSH-Login (optional):** Repository-Secret `SSH_AUTHORIZED_KEYS` anlegen
(Settings → Secrets and variables → Actions) mit Deinem/n Public Key(s).
Das Image enthält dann `openssh-server` mit Key-Login.

Hinweise:
- Der Workflow läuft auf den kostenlosen `ubuntu-24.04`-Runnern und nutzt KVM für debos.
  Ohne KVM fällt er auf qemu-Emulation zurück, was Stunden dauert (Job-Limit 6 h).
- Für Releases braucht der Workflow `contents: write` (ist bereits gesetzt).

```
Run workflow ─▶ Platz schaffen ─▶ KVM aktivieren ─▶ ./build.sh -K (Kernel + debs)
             ─▶ .deb-Artefakt hochladen ─▶ ./build.sh -I (debos-Image)
             ─▶ Image-Artefakt hochladen ─▶ gh release create
```

## Lokal bauen

Voraussetzungen: Linux x86_64 oder arm64, Docker, ~25 GB freier Platz,
idealerweise `/dev/kvm` (sonst langsame qemu-Emulation in debos).

```bash
./build.sh                       # Phosh, Benutzer mobian / 1234
./build.sh -e plasma-mobile      # Plasma Mobile
./build.sh -u dennis -p 4711 -H poco -s ~/.ssh/id_ed25519.pub
./build.sh -K                    # nur Kernel + Gerätepakete
./build.sh -I                    # nur das Image (nutzt out/packages)
KERNEL_TAG=v7.1.0-sm8150 ./build.sh   # andere Kernelversion
```

Ergebnisse:
- `out/packages/` – `linux-image-*-sm8150-vayu`, `firmware-xiaomi-vayu`, `mobian-xiaomi-vayu-tweaks`
- `out/images/` – `mobian-vayu-<env>-<datum>.boot-vayu-{huaxing,tianma}.img`, `.rootfs.img`,
  `.tar.xz` (beides zusammen), `.sha256sums`, `flash.sh`

Heruntergeladene Quellen werden in `work/dl/` zwischengespeichert. Komplett neu anfangen:
`rm -rf work out`.

## Flashen

Voraussetzungen: **entsperrter Bootloader**, `fastboot` (optional `adb`) auf dem PC
(`sudo apt install fastboot adb`).

1. Optional – Panel ermitteln: Android (oder TWRP/OrangeFox) starten, USB-Debugging
   aktivieren, verbinden und `./flash.sh --detect-panel` ausführen.
2. Telefon ausschalten, **Leiser + Power** halten → Fastboot-Modus, USB verbinden.
3. Im Ordner mit den Images (Release-Download oder `out/images/`):

   ```bash
   ./flash.sh                     # erkennt/fragt das Panel, fragt nach Bestätigung
   ./flash.sh --panel tianma -y   # ohne Rückfragen
   ```

`flash.sh` macht Folgendes:
1. prüft die Prüfsummen und ob das Gerät wirklich `vayu`/`bhima` ist,
2. `fastboot erase dtbo` (die Android-DT-Overlays stören den Mainline-Kernel),
3. `fastboot flash boot <boot-vayu-PANEL.img>`,
4. `fastboot flash userdata <rootfs.img>` (**löscht alle Benutzerdaten**),
5. `fastboot reboot`.

Weitere Optionen: `--boot-only` (nur Panel/Kernel wechseln), `--keep-dtbo`,
`--vbmeta DATEI` (vbmeta mit deaktivierter Verifikation flashen, falls die Firmware das
braucht), `--no-reboot`. `./flash.sh --help` zeigt alle.

Standard-Login: **mobian / 1234** (bzw. was beim Build gewählt wurde).

### Zurück zu Android

Das offizielle MIUI/HyperOS-**Fastboot-ROM** für vayu herunterladen und mit
`flash_all.sh` flashen – das stellt `boot`, `dtbo`, `vbmeta` und `userdata` wieder her.

## Erste Schritte nach dem Booten

```bash
sudo apt update && sudo apt full-upgrade
# Falls das Root-Dateisystem nicht die ganze userdata-Partition nutzt:
sudo resize2fs "$(findmnt -n -o SOURCE /)"
```

Kernel-Updates kommen für dieses Gerät nicht aus den Mobian-Repositories. Zum
Aktualisieren einen neuen Build starten und das neue `linux-image-*.deb` auf dem Telefon
mit `sudo apt install ./linux-image-*.deb` installieren, danach das passende Boot-Image
flashen (`./flash.sh --boot-only`) – oder einfach ein neues Image flashen.

## Fehlersuche

| Problem | Lösung |
|---|---|
| Schwarzer Bildschirm nach dem Boot | Falsches Panel → `./flash.sh --boot-only --panel <anderes>` |
| Zurück im Fastboot / Bootloop | Prüfen, dass `--keep-dtbo` nicht genutzt wurde; `--vbmeta vbmeta.img` aus dem Stock-ROM probieren |
| Kein WLAN / Audio | `dmesg` auf Firmware-Fehler prüfen (`/usr/lib/firmware/qcom/sm8150/Xiaomi/vayu/`) |
| debos scheitert mit KVM-Fehler | `ls -l /dev/kvm`; Benutzer in Gruppe `kvm` aufnehmen oder qemu-Fallback nutzen |
| `Checksum mismatch` | Upstream-Archiv geändert → Hashes in `versions.env` aktualisieren |

Debuggen über USB: Mobian stellt eine USB-Netzwerkschnittstelle bereit; mit eingebautem
SSH-Key (`-s` / Secret `SSH_AUTHORIZED_KEYS`) per `ssh mobian@10.66.0.1` einloggen.

## Danksagung

- [Mobian](https://mobian-project.org/) / [mobian-recipes](https://salsa.debian.org/Mobian-team/mobian-recipes) – Build-System
- [postmarketOS](https://postmarketos.org/)-Port für vayu (Arseniy Velikanov, Ali Nasrullayev)
  – Kernelconfig, Patches, Firmware-Paketierung, ALSA-UCM
- [sm8150-mainline](https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux) – Kernel

Die Firmware ist proprietär und wird nur zur Build-Zeit heruntergeladen; sie ist nicht Teil
dieses Repositorys.
