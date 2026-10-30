# larch-kernel

The kernel for [larch-os](https://github.com/kuhwar/larch-os): Debian trixie's
own `linux-source-6.12`, built with Debian's amd64 config, with only the drivers
needed to mount the root filesystem switched from modules to built-in:

| Option | Why |
|---|---|
| `SQUASHFS`, `SQUASHFS_ZSTD` | root: `LARCHSYS` is the zstd squashfs image written raw onto the partition |
| `EXT4_FS` | the other larch-os partitions (`LARCHCONF`, `LARCHHOME`) |
| `BLK_DEV_NVME` | NVMe SSDs |
| `ATA`, `SATA_AHCI`, `SCSI`, `BLK_DEV_SD` | SATA disks |
| `VIRTIO_BLK`, `SCSI_VIRTIO` | QEMU/KVM disks |
| `USB`, `USB_STORAGE`, `USB_UAS`, xHCI/EHCI/OHCI/UHCI host controllers | USB disks |

That lets larch-os boot with **no initramfs**: the kernel mounts
`root=PARTLABEL=LARCHSYS rootfstype=squashfs` itself. Everything else is as Debian ships it (still
modules). Debug info is off, and Debian's signing-key paths are cleared since
they only exist in Debian's own build.

A Renesas uPD72020x USB 3 controller without a ROM needs firmware the kernel
can't read before root is mounted, so a disk behind one won't boot.

## Releases

Built by the **Build kernel** workflow, run manually (Actions → Build kernel →
Run workflow). Each release is tagged `<Debian version>.larch<CFG_REV>`, e.g.
`6.12.113-1.larch1`, and carries:

- `linux-image-<ver>-larch_<tag>_amd64.deb`
- `linux-headers-<ver>-larch_<tag>_amd64.deb` (for DKMS: nvidia, broadcom-sta)
- `config` (the full kernel config)

If a release for the current Debian version already exists, the run skips the
build unless **force** is ticked. Bump `CFG_REV` in `build-kernel.sh` when the
config changes.

larch-os's build downloads the latest release (`scripts/fetch-kernel.sh`).

## Building locally

```bash
docker run --rm -v "$PWD:/src" -w /src debian:trixie \
    sh -c './install-deps.sh && ./build-kernel.sh /src/out'
```

The `.deb`s land in `out/` (root-owned, since the container runs as root). To
use them in a larch-os build without publishing a release, copy them into
larch-os's `kernel-cache/` and mark them as local:

```bash
cp out/*.deb ../larch-os/kernel-cache/ && echo local > ../larch-os/kernel-cache/.tag
```
