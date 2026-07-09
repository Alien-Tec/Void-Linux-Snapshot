# GNUSlashLinux_Void_Snapshot

# 🌀 GNUSlashLinux Snapshot Generator

Ein mächtiges, automatisiertes CLI-Werkzeug zur Erstellung eines bootfähigen **1:1 Live-ISO-Abbilds** deines laufenden Systems. Das Projekt basiert auf Void Linux, liefert jedoch ein vollständig angepasstes Branding für **GNUSlashLinux**.

Dieses Skript verhält sich ähnlich wie *Remastersys* oder *Refractasnapshot*, ist jedoch von Grund auf für die Besonderheiten von `runit` und `XBPS` optimiert.

---

## ✨ Features

* **1:1 Desktop-Klon:** Übernimmt deine komplette Umgebung (Niri, Material Shell, Waybar, alle installierten Programme und Konfigurationen).
* **Universelle Kompatibilität:** Generiert über `dracut` ein hardware-unabhängiges Initramfs. Das ISO bootet auf jedem x86_64 PC.
* **Privatsphäre-Schutz:** Entfernt automatisch sensible Daten (WLAN-Passwörter, Browser-Caches, SSH-Host-Keys, `.ssh`-Ordner).
* **Nahtloses Branding:** Übernimmt und integriert deine aktiven Themes für **GRUB, Plymouth und SDDM**.
* **Live-User-Umwandlung:** Löscht Altnutzer im ISO und migriert dein gesamtes Home-Verzeichnis sicher auf den Standard-User `anon` (Passwort: `voidlinux`).
* **Interaktiv:** Fragt vor dem Start den gewünschten ISO-Namen sowie die SquashFS-Komprimierungsrate (`xz`, `gzip`, `lz4`) ab.

---

## 🚀 Vorbereitung & Erstellung

1. Lade das Skript herunter und mache es ausführbar:
   ```bash
   chmod +x gnuslashlinux-snapshot.sh
   ```

2. Starte das Skript über deinen normalen Benutzer mittels `sudo`:
   ```bash
   sudo ./gnuslashlinux-snapshot.sh
   ```

3. Folge den interaktiven Anweisungen im Terminal. Nach Abschluss findest du dein fertiges ISO-Image im Verzeichnis `/home/snapshot/`.

4. Flashe das ISO auf einen USB-Stick (z. B. mit `dd` oder [Ventoy](https://ventoy.net)):
   ```bash
   sudo dd if=/home/snapshot/dein-iso-name.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```
   *(Ersetze `sdX` durch die tatsächliche Bezeichnung deines USB-Sticks!)*

