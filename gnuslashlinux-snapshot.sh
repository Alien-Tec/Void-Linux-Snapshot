#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "[!] Bitte starte das Skript mit sudo!"
  exit 1
fi

REAL_USER="$SUDO_USER"
if [ -z "$REAL_USER" ] || [ "$REAL_USER" == "root" ]; then
  echo "[!] Fehler: Bitte mit 'sudo ./gnuslashlinux-snapshot.sh' vom normalen User aus starten."
  exit 1
fi

WORKDIR="/tmp/gnuslashlinux-snapshot-build"
TARGET_DIR="/home/snapshot"

# Sicherheits-Cleanup-Funktion NUR für unvorhergesehene Abbrüche (Fehler oder Strg+C)
cleanup_on_error() {
  echo ""
  echo "[!] Fehler oder Abbruch erkannt! Bereinige Mount-Pfade..."
  # Erzwungenes und träges (lazy) Aushängen aller Kernel-Schnittstellen
  umount -l -R "$WORKDIR/rootfs/dev" 2>/dev/null
  umount -l "$WORKDIR/rootfs/proc" 2>/dev/null
  umount -l "$WORKDIR/rootfs/sys" 2>/dev/null
  umount -l "$WORKDIR/rootfs/run" 2>/dev/null
  
  if [ -d "$WORKDIR" ]; then
    echo "[i] Entferne unvollständige Build-Dateien..."
    rm -rf "$WORKDIR"
  fi
  exit 1
}
# Registriere den Trap für Signale und Fehler
trap cleanup_on_error SIGINT SIGTERM ERR

echo "==============================================="
echo "    GNUSlashLinux ISO-Snapshot Generator      "
echo "==============================================="

# 1. Vorab-Check für den benötigten Speicherplatz
NEEDED_GB=$(du -s / --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/tmp --exclude=/mnt --exclude=/media 2>/dev/null | awk '{print int($1/1024/1024 * 2.1)}')
AVAILABLE_GB=$(df -BG /tmp | tail -1 | awk '{print $4}' | sed 's/G//')

echo "[i] Geschätzter temporärer Platzbedarf: ~${NEEDED_GB} GB"
echo "[i] Verfügbarer Platz in /tmp: ${AVAILABLE_GB} GB"
if [ "$NEEDED_GB" -gt "$AVAILABLE_GB" ]; then
  echo "[!] WARNUNG: Zu wenig Platz in /tmp! Fortfahren auf eigene Gefahr."
  read -p "Trotzdem fortfahren? (j/N): " CONFIRM
  [[ "$CONFIRM" =~ ^[Jj]$ ]] || exit 1
fi

# --- INTERAKTIVE ABFRAGEN ---
read -p "Gib den Namen für das ISO an (ohne .iso) [gnuslashlinux-snapshot]: " INPUT_NAME
ISO_BASE_NAME=${INPUT_NAME:-gnuslashlinux-snapshot}
ISO_NAME="${ISO_BASE_NAME}-$(date +%Y%m%d).iso"

echo "Wähle die SquashFS Komprimierungsrate:"
echo "1) xz    (Maximale Komprimierung, dauert am längsten)"
echo "2) gzip  (Schnell, mittlere Dateigröße)"
echo "3) lz4   (Extrem schnell, größte Datei)"
read -p "Auswahl (1-3): " COMP_CHOICE

case "$COMP_CHOICE" in
  2) COMP_MODE="gzip";;
  3) COMP_MODE="lz4";;
  *) COMP_MODE="xz";;
esac

TARGET_ISO="$TARGET_DIR/$ISO_NAME"

echo "=================================================="
echo "Starte Snapshot: $ISO_NAME (Comp: $COMP_MODE)"
echo "=================================================="

# UEFI-Bootfähigkeit für das ISO garantieren
xbps-install -Sy squashfs-tools xorriso libisoburn rsync perl dracut grub-x86_64-efi mtools

# Altes Verzeichnis vor dem Start sauber aufräumen
if [ -d "$WORKDIR" ]; then
  umount -l -R "$WORKDIR/rootfs/dev" 2>/dev/null
  umount -l "$WORKDIR/rootfs/proc" 2>/dev/null
  umount -l "$WORKDIR/rootfs/sys" 2>/dev/null
  umount -l "$WORKDIR/rootfs/run" 2>/dev/null
  rm -rf "$WORKDIR"
fi

mkdir -p "$WORKDIR/rootfs" "$WORKDIR/iso/boot/grub" "$TARGET_DIR"

echo "[1/7] Kopiere das komplette System 1:1 (Netzwerk & Caches geschützt)..."
rsync -aHAXx / "$WORKDIR/rootfs/" \
  --exclude=/proc/* --exclude=/sys/* --exclude=/dev/* --exclude=/run/* \
  --exclude=/tmp/* --exclude=/mnt/* --exclude=/media/* --exclude=/lost+found \
  --exclude=/var/cache/xbps/* --exclude="$WORKDIR" --exclude="$TARGET_DIR" \
  --exclude="/home/$REAL_USER/.cache/*" \
  --exclude="/home/$REAL_USER/.mozilla/*" \
  --exclude="/home/$REAL_USER/.config/google-chrome/*" \
  --exclude=/etc/NetworkManager/system-connections/* \
  --exclude=/etc/wpa_supplicant/wpa_supplicant*.conf \
  --exclude=/var/lib/NetworkManager/* \
  --exclude=/etc/ssh/ssh_host_*_key* \
  --exclude="/home/$REAL_USER/.ssh/*" \
  --exclude=/etc/udev/rules.d/70-persistent-net.rules \
  --exclude=/var/log/*

# Systeminterne Mountpoints leer wiederherstellen
mkdir -p "$WORKDIR/rootfs"/{proc,sys,dev,run,tmp,mnt,media}
chmod 1777 "$WORKDIR/rootfs/tmp"
echo "[2/7] Passe Benutzerkonten an: Erstelle Live-User 'anon'..."
sed -i -E "/^[^:]+:x:[0-9]{4,}:/d" "$WORKDIR/rootfs/etc/passwd"
sed -i -E "/^[^:]+:x:[0-9]{4,}:/d" "$WORKDIR/rootfs/etc/group"
sed -i -E "/^[^:]+:[^:]+:[0-9]{4,}:/d" "$WORKDIR/rootfs/etc/shadow"
sed -i -E "/^[^:]+:[^:]+:[0-9]{4,}:/d" "$WORKDIR/rootfs/etc/gshadow"

ANON_HASH=$(perl -e 'print crypt("voidlinux", "\$6\$saltsalt\$")')
echo "anon:x:1000:1000:Live User:/home/anon:/bin/bash" >> "$WORKDIR/rootfs/etc/passwd"
echo "anon:x:1000:" >> "$WORKDIR/rootfs/etc/group"
echo "anon:${ANON_HASH}:19000:0:99999:7:::" >> "$WORKDIR/rootfs/etc/shadow"

# Gruppen-Mitgliedschaften für 'anon' eintragen
for grp in wheel audio video input storage; do
  if grep -q "^${grp}:" "$WORKDIR/rootfs/etc/group"; then
    sed -i "s/\(^${grp}:x:[0-9]*:\)\(.*\)/\1\2,anon/;s/,,/,/;s/:\,/:/" "$WORKDIR/rootfs/etc/group" 2>/dev/null || true
  fi
done

if [ -d "$WORKDIR/rootfs/home/$REAL_USER" ]; then
  mv "$WORKDIR/rootfs/home/$REAL_USER" "$WORKDIR/rootfs/home/anon"
  chown -R 1000:1000 "$WORKDIR/rootfs/home/anon"
fi

echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "$WORKDIR/rootfs/etc/sudoers.d/live"

echo "[3/7] Konfiguriere Distribution GNUSlashLinux, SDDM-Autologin & Themes..."
echo "GNUSlashLinux-Snapshot" > "$WORKDIR/rootfs/etc/hostname"

rm -f "$WORKDIR/rootfs/var/lock/.xbps.lock"
cp /etc/resolv.conf "$WORKDIR/rootfs/etc/resolv.conf"
chroot "$WORKDIR/rootfs" xbps-remove -Oy 2>/dev/null || true
echo "nameserver 1.1.1.1" > "$WORKDIR/rootfs/etc/resolv.conf"

echo -n "" > "$WORKDIR/rootfs/etc/machine-id"

if [ -f "$WORKDIR/rootfs/etc/os-release" ]; then
  sed -i 's/^NAME=.*/NAME="GNUSlashLinux"/' "$WORKDIR/rootfs/etc/os-release"
  sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="GNUSlashLinux (Void-based)"/' "$WORKDIR/rootfs/etc/os-release"
  sed -i 's/^ID=.*/ID="gnuslashlinux"/' "$WORKDIR/rootfs/etc/os-release"
fi

if [ -f /etc/plymouth/plymouthd.conf ]; then
  cp /etc/plymouth/plymouthd.conf "$WORKDIR/rootfs/etc/plymouth/plymouthd.conf"
fi

NIRI_SESSION=$(basename "$(ls /usr/share/wayland-sessions/niri*.desktop 2>/dev/null | head -n 1)" .desktop)
[ -z "$NIRI_SESSION" ] && NIRI_SESSION="niri"

CURRENT_SDDM_THEME=$(grep -Po '(?<=Current=).*' /etc/sddm.conf /etc/sddm.conf.d/* 2>/dev/null | head -n 1)
[ -z "$CURRENT_SDDM_THEME" ] && CURRENT_SDDM_THEME="breeze"

mkdir -p "$WORKDIR/rootfs/etc/sddm.conf.d"
cat << EOF > "$WORKDIR/rootfs/etc/sddm.conf.d/live.conf"
[Autologin]
User=anon
Session=${NIRI_SESSION}

[Theme]
Current=${CURRENT_SDDM_THEME}
EOF

mkdir -p "$WORKDIR/rootfs/etc/polkit-1/rules.d"
cat << EOF > "$WORKDIR/rootfs/etc/polkit-1/rules.d/49-live-admin.rules"
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    fi
});
EOF
chmod 700 "$WORKDIR/rootfs/etc/polkit-1/rules.d"
chown -R root:root "$WORKDIR/rootfs/etc/polkit-1/rules.d"

mkdir -p "$WORKDIR/rootfs/etc/local.d"
cat << 'EOF' > "$WORKDIR/rootfs/etc/local.d/99-audio-init.start"
#!/bin/sh
if command -v amixer >/dev/null 2>&1; then
    amixer sset Master unmute 30% >/dev/null 2>&1
    amixer sset Speaker unmute 30% >/dev/null 2>&1
    amixer sset Headphone unmute 30% >/dev/null 2>&1
fi
EOF
chmod +x "$WORKDIR/rootfs/etc/local.d/99-audio-init.start"

mkdir -p "$WORKDIR/rootfs/etc/runit/runsvdir/default"
ln -sf /etc/sv/local "$WORKDIR/rootfs/etc/runit/runsvdir/default/local"

echo "[4/7] Bereite Live-Boot (fstab) vor..."
echo "tmpfs / tmpfs defaults 0 0" > "$WORKDIR/rootfs/etc/fstab"
echo "proc /proc proc defaults 0 0" >> "$WORKDIR/rootfs/etc/fstab"
echo "sysfs /sys sysfs defaults 0 0" >> "$WORKDIR/rootfs/etc/fstab"

echo "[5/7] Generiere universelles Initramfs mit Live-Modulen..."
KERNEL_VERSION=$(uname -r)

# Dracut-Warnungen und unkritische Mount-Verzögerungen temporär ignorieren
trap - ERR

# Isoliertes /run als tmpfs einbinden, um Dracut-Lock-Fehler im Chroot zu unterbinden
mount --bind /dev "$WORKDIR/rootfs/dev"
mount --bind /dev/pts "$WORKDIR/rootfs/dev/pts"
mount --bind /proc "$WORKDIR/rootfs/proc"
mount --bind /sys "$WORKDIR/rootfs/sys"
mount -t tmpfs tmpfs "$WORKDIR/rootfs/run"

# --tmpdir /tmp hinzugefügt, um dracut von Host-Sperren abzukoppeln
chroot "$WORKDIR/rootfs" dracut --no-hostonly --tmpdir /tmp --add "dmsquash-live livenet" --force "/boot/initramfs-live.img" "$KERNEL_VERSION"

# Träges Aushängen aller Schnittstellen nach der Generierung
umount -l -R "$WORKDIR/rootfs/dev"
umount -l "$WORKDIR/rootfs/proc"
umount -l "$WORKDIR/rootfs/sys"
umount -l "$WORKDIR/rootfs/run"

# Erst JETZT den Trap für die nachfolgenden Hauptprozesse (SquashFS & xorriso) wieder aktivieren
trap cleanup_on_error SIGINT SIGTERM ERR

echo "[6/7] Erstelle SquashFS-Dateisystem (Das kann dauern)..."
mkdir -p "$WORKDIR/iso/live"
mksquashfs "$WORKDIR/rootfs" "$WORKDIR/iso/live/rootfs.squashfs" -comp "$COMP_MODE"

echo "[7/7] Generiere Grub Bootloader für das ISO..."
cp "/boot/vmlinuz-$KERNEL_VERSION" "$WORKDIR/iso/boot/vmlinuz"
cp "$WORKDIR/rootfs/boot/initramfs-live.img" "$WORKDIR/iso/boot/initramfs"

ACTIVE_GRUB_THEME=$(grep -Po '(?<=GRUB_THEME=").*(?=")' /etc/default/grub 2>/dev/null)
if [ -n "$ACTIVE_GRUB_THEME" ] && [ -d "$ACTIVE_GRUB_THEME" ]; then
  mkdir -p "$WORKDIR/iso/boot/grub/themes/custom"
  cp -r "$(dirname "$ACTIVE_GRUB_THEME")"/* "$WORKDIR/iso/boot/grub/themes/custom/"
  THEME_LINE="set theme=/boot/grub/themes/custom/theme.txt"
fi

cat << EOF > "$WORKDIR/iso/boot/grub/grub.cfg"
insmod png
insmod jpeg
insmod ext2
$THEME_LINE
set default="0"
set timeout=10

menuentry "GNUSlashLinux Live Snapshot ($ISO_BASE_NAME)" {
    set gfxpayload=keep
    linux /boot/vmlinuz root=live:CDLABEL=GNUSLASH_SNAPSHOT init=/sbin/init ro quiet splash
    initrd /boot/initramfs
}
EOF

grub-mkrescue -o "$TARGET_ISO" "$WORKDIR/iso" -- -volid "GNUSLASH_SNAPSHOT"

if [ $? -eq 0 ]; then
  echo "=================================================="
  echo "[✓] Erfolg! Deine 1:1 Snapshot-ISO wurde erstellt."
  echo "Datei: $TARGET_ISO"
  echo "User: anon | Passwort: voidlinux"
  echo "=================================================="
else
  echo "[!] Fehler beim Erstellen der ISO."
fi

# Reguläres Aufräumen am Ende des Skripts (deaktiviert den Fehler-Trap)
trap - SIGINT SIGTERM ERR EXIT
rm -rf "$WORKDIR"
