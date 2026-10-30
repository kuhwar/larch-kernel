#!/bin/bash
# build-kernel.sh — build the larch-os kernel packages
#
# Rebuilds Debian's own kernel (linux-source-6.12 + its amd64 config from
# linux-config-6.12) with the drivers needed to mount the root filesystem
# switched from modules to built-in, so larch-os boots with no initramfs: the
# kernel itself mounts root=PARTLABEL=LARCHSYS. Everything else stays exactly
# as Debian ships it.
#
# Runs on Debian trixie with the packages from install-deps.sh installed
# (the CI workflow and the local docker one-liner in README.md both do that).
#
# Usage:
#   build-kernel.sh <out-dir>   build; writes linux-image-*.deb, linux-headers-*.deb
#                               and RELEASE (the release tag) into <out-dir>
#   build-kernel.sh --tag       print the release tag for the current Debian
#                               source version without building

set -euo pipefail

log() { echo "  [kernel] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Bump when the config changes below, so a new release is cut for the same
# Debian source version.
CFG_REV=2
SRC_PKG=linux-source-6.12

# Installed version of the Debian source package, else apt's candidate.
deb_ver() {
    dpkg-query -W -f='${Version}' "$SRC_PKG" 2>/dev/null ||
        apt-cache policy "$SRC_PKG" | awk '/Candidate:/ { print $2 }'
}

if [ "${1:-}" = "--tag" ]; then
    echo "$(deb_ver).larch$CFG_REV"
    exit 0
fi

OUT="${1:?usage: build-kernel.sh <out-dir> | --tag}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

SRC_TAR=$(ls /usr/src/$SRC_PKG.tar.xz 2>/dev/null || true)
[ -f "$SRC_TAR" ] || die "$SRC_PKG tarball not found in /usr/src (run install-deps.sh)"
DEB_VER=$(deb_ver)                                   # e.g. 6.12.113-1
CFG_XZ="/usr/src/linux-config-${SRC_PKG#linux-source-}/config.amd64_none_amd64.xz"
[ -f "$CFG_XZ" ] || die "Debian kernel config not found: $CFG_XZ (run install-deps.sh)"
TAG="$DEB_VER.larch$CFG_REV"

log "Building $SRC_PKG $DEB_VER → release $TAG"
# KBUILD_DIR is where the build tree goes (CI points it at a mounted scratch
# disk); build in a subdirectory, since a mount point itself can't be removed.
BUILD="${KBUILD_DIR:-/var/tmp}/larch-kbuild"
rm -rf "$BUILD"
mkdir -p "$BUILD"
tar -xaf "$SRC_TAR" -C "$BUILD"
cd "$BUILD/$SRC_PKG"

xzcat "$CFG_XZ" > .config

# Root-mount path, built in:
#   SQUASHFS + SQUASHFS_ZSTD — LARCHSYS: the zstd squashfs image, written raw
#                  onto the partition (root=PARTLABEL=LARCHSYS rootfstype=squashfs)
#   EXT4_FS      — the LARCHCONF / LARCHHOME filesystem
#   BLK_DEV_NVME — NVMe SSDs
#   ATA + SATA_AHCI + SCSI + BLK_DEV_SD — SATA disks (libata sits on SCSI)
#   VIRTIO_BLK + SCSI_VIRTIO — QEMU/KVM disks
#   USB + USB_STORAGE + USB_UAS — USB disks (on SCSI too), behind the xHCI
#                  (USB 3), EHCI (USB 2) and OHCI/UHCI (USB 1.1) host controllers.
#                  XHCI_PCI_RENESAS must be built in too, or Kconfig holds
#                  XHCI_PCI at =m; a Renesas uPD72020x without a ROM still
#                  needs its firmware, which isn't readable before root mounts.
#
# Debian-specific settings that don't work outside Debian's build:
#   SYSTEM_TRUSTED_KEYS — points at debian/certs/, not in linux-source
#   DEBUG_INFO          — off: halves build time, no -dbg package
scripts/config --file .config \
    --set-str LOCALVERSION "-larch" \
    --enable  SQUASHFS \
    --enable  SQUASHFS_ZSTD \
    --enable  EXT4_FS \
    --enable  BLK_DEV_NVME \
    --enable  ATA \
    --enable  SATA_AHCI \
    --enable  SCSI \
    --enable  BLK_DEV_SD \
    --enable  VIRTIO_BLK \
    --enable  SCSI_VIRTIO \
    --enable  USB \
    --enable  USB_XHCI_HCD \
    --enable  USB_XHCI_PCI \
    --enable  USB_XHCI_PCI_RENESAS \
    --enable  USB_EHCI_HCD \
    --enable  USB_EHCI_PCI \
    --enable  USB_OHCI_HCD \
    --enable  USB_OHCI_HCD_PCI \
    --enable  USB_UHCI_HCD \
    --enable  USB_STORAGE \
    --enable  USB_UAS \
    --set-str SYSTEM_TRUSTED_KEYS "" \
    --set-str SYSTEM_REVOCATION_KEYS "" \
    --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
    --disable DEBUG_INFO_DWARF4 \
    --disable DEBUG_INFO_DWARF5 \
    --disable DEBUG_INFO_BTF \
    --enable  DEBUG_INFO_NONE
make olddefconfig >/dev/null

for opt in SQUASHFS SQUASHFS_ZSTD EXT4_FS BLK_DEV_NVME ATA SATA_AHCI SCSI BLK_DEV_SD \
           VIRTIO_BLK SCSI_VIRTIO USB USB_XHCI_HCD USB_XHCI_PCI USB_XHCI_PCI_RENESAS \
           USB_EHCI_HCD USB_EHCI_PCI USB_OHCI_HCD USB_OHCI_HCD_PCI USB_UHCI_HCD \
           USB_STORAGE USB_UAS; do
    grep -qx "CONFIG_$opt=y" .config || die "CONFIG_$opt did not end up built-in (=y) after olddefconfig"
done
log "Root-mount drivers are built in"
cp .config "$OUT/config"

# DPKG_FLAGS=-d: skip dpkg-buildpackage's build-dep check (it wants the
# triplet-named gcc package; plain gcc is the same compiler natively).
make -j"$(nproc)" bindeb-pkg DPKG_FLAGS=-d KDEB_PKGVERSION="$TAG"

rm -f "$OUT"/*.deb
cp "$BUILD"/linux-image-*-larch_*.deb "$BUILD"/linux-headers-*-larch_*.deb "$OUT/"
echo "$TAG" > "$OUT/RELEASE"
rm -rf "$BUILD"
log "Built: $(cd "$OUT" && ls ./*.deb | tr '\n' ' ')"
