# Mobian for the Xiaomi POCO X3 Pro (vayu)

🇩🇪 [Deutsche Version](README.de.md)

Build scripts, flash script and a GitHub Actions workflow that produce a flashable
[Mobian](https://mobian-project.org/) (Debian for phones) image for the
**Xiaomi POCO X3 Pro** (codename `vayu`, also `bhima`, Snapdragon 860 / SM8150).

> ⚠️ **Unofficial and experimental.** Mobian does not support vayu officially.
> This project uses Mobian's own `qcom-wip` porting mechanism together with the
> mainline SM8150 kernel and firmware from the
> [postmarketOS vayu port](https://wiki.postmarketos.org/wiki/Xiaomi_POCO_X3_Pro_(xiaomi-vayu)).
> Expect the same hardware support as postmarketOS — in particular, **the modem
> (calls / SMS / mobile data) is not reliably working** on mainline yet.
> **Flashing erases all data on the phone and removes Android.**

## How it works

```
┌──────────────────────────┐   ┌──────────────────────────┐   ┌──────────────────────────────┐
│ 1. Kernel (.deb)         │   │ 2. Device packages (.deb)│   │ 3. Image (debos)             │
│ sm8150-mainline v7.0.0   │──▶│ firmware-xiaomi-vayu     │──▶│ mobian-recipes, qcom-wip     │
│ + pmOS patches & config  │   │ mobian-xiaomi-vayu-tweaks│   │ config/vayu.toml             │
│ make bindeb-pkg (clang)  │   │ (UCM audio profile)      │   │ → boot-vayu-{huaxing,tianma} │
└──────────────────────────┘   └──────────────────────────┘   │ → rootfs.img (sparse)        │
                                                              └──────────────────────────────┘
```

| Path | Content |
|---|---|
| `build.sh` | One command for the whole build (everything runs in Docker) |
| `flash.sh` | Flashes the result via fastboot (with panel detection) |
| `versions.env` | Pinned versions + checksums of kernel, firmware, mobian-recipes |
| `config/vayu.toml` | Mobian device config (boot image offsets, DTB names, panel variants) |
| `kernel/` | postmarketOS kernel config, patches, Mobian config fragment |
| `device/` | ALSA UCM profile; files in `device/rootfs/` (optional) end up in the image |
| `scripts/` | Individual build steps |
| `.github/workflows/build.yml` | Build in GitHub Actions with one click |

### Display panel variants

The POCO X3 Pro ships with one of two display panels, **Huaxing** or **Tianma**,
which need different device trees. Every build therefore produces two boot images:
`*.boot-vayu-huaxing.img` and `*.boot-vayu-tianma.img`. The rootfs is the same.
Picking the wrong one is harmless: the screen stays black — just flash the other
boot image (`./flash.sh --boot-only --panel <other>`).

## Build with GitHub Actions (one click)

1. Push this folder to a GitHub repository.
2. Go to **Actions → "Build Mobian image (POCO X3 Pro / vayu)" → Run workflow**.
3. Choose the options:
   - **environment**: `phosh` (default), `plasma-mobile` or `lomiri`
   - **username / password**: default user (default `mobian` / `1234`, visible in the log!)
   - **kernel_tag**: empty = pinned version; otherwise e.g. `v7.1.0-sm8150`
   - **recipes_ref**: empty = pinned mobian-recipes commit; e.g. `master`
   - **release**: publish the result as a GitHub release
4. After ~1–2 hours the image is available
   - as a **Release** (tag `vayu-<env>-<date>-<run>`) and
   - as a workflow **artifact** (kept for 7 days), plus the `.deb` packages (14 days).

**SSH login (optional):** create the repository secret `SSH_AUTHORIZED_KEYS`
(Settings → Secrets and variables → Actions) containing your public key(s).
The image then has `openssh-server` with key login enabled.

Notes:
- The workflow runs on the free `ubuntu-24.04` runners and uses KVM for debos.
  Without KVM it falls back to qemu emulation, which takes hours (the job limit is 6 h).
- The workflow needs `contents: write` permission (already set) to create releases.

```
Run workflow ─▶ Free disk ─▶ Enable KVM ─▶ ./build.sh -K (kernel + debs)
             ─▶ upload .deb artifact ─▶ ./build.sh -I (debos image)
             ─▶ upload image artifact ─▶ gh release create
```

## Build locally

Requirements: Linux x86_64 or arm64, Docker, ~25 GB free disk space,
ideally `/dev/kvm` (otherwise debos falls back to slow qemu emulation).

```bash
./build.sh                       # Phosh, user mobian / 1234
./build.sh -e plasma-mobile      # Plasma Mobile
./build.sh -u dennis -p 4711 -H poco -s ~/.ssh/id_ed25519.pub
./build.sh -K                    # only kernel + device packages
./build.sh -I                    # only the image (re-uses out/packages)
KERNEL_TAG=v7.1.0-sm8150 ./build.sh   # different kernel version
```

Results:
- `out/packages/` – `linux-image-*-sm8150-vayu`, `firmware-xiaomi-vayu`, `mobian-xiaomi-vayu-tweaks`
- `out/images/` – `mobian-vayu-<env>-<date>.boot-vayu-{huaxing,tianma}.img`, `.rootfs.img`,
  `.tar.xz` (both together), `.sha256sums`, `flash.sh`

Downloaded sources are cached in `work/dl/`. To start completely fresh: `rm -rf work out`.

## Flashing

Requirements: **unlocked bootloader**, `fastboot` (and optionally `adb`) on the PC
(`sudo apt install fastboot adb`).

1. Optional – find out the panel: boot Android (or TWRP/OrangeFox), enable USB debugging,
   connect and run `./flash.sh --detect-panel`.
2. Turn the phone off, hold **Volume down + Power** → fastboot mode, connect USB.
3. In the folder with the images (release download or `out/images/`):

   ```bash
   ./flash.sh                     # asks for / detects the panel, asks for confirmation
   ./flash.sh --panel tianma -y   # non-interactive
   ```

`flash.sh` will:
1. verify the checksums and that the device really is `vayu`/`bhima`,
2. `fastboot erase dtbo` (the Android DT overlays break the mainline kernel),
3. `fastboot flash boot <boot-vayu-PANEL.img>`,
4. `fastboot flash userdata <rootfs.img>` (**erases all user data**),
5. `fastboot reboot`.

Other options: `--boot-only` (switch panel/kernel only), `--keep-dtbo`,
`--vbmeta FILE` (flash vbmeta with verification disabled, if your firmware needs it),
`--no-reboot`. `./flash.sh --help` shows all of them.

Default login: **mobian / 1234** (or what you chose at build time).

### Back to Android

Download the official MIUI/HyperOS **fastboot ROM** for vayu and flash it with
`flash_all.sh` — that restores `boot`, `dtbo`, `vbmeta` and `userdata`.

## First steps after booting

```bash
sudo apt update && sudo apt full-upgrade
# If the root filesystem does not span the whole userdata partition:
sudo resize2fs "$(findmnt -n -o SOURCE /)"
```

Kernel updates are not provided by Mobian's repositories for this device. To update
the kernel, run a new build and install the new `linux-image-*.deb` on the phone with
`sudo apt install ./linux-image-*.deb`, then re-flash the matching boot image
(`./flash.sh --boot-only`) — or flash a new image.

## Troubleshooting

| Problem | Solution |
|---|---|
| Black screen after boot | Wrong panel → `./flash.sh --boot-only --panel <other>` |
| Back in fastboot / bootloop | Check `--keep-dtbo` was not used; try `--vbmeta vbmeta.img` from the stock ROM |
| No WiFi / audio | Check `dmesg` for firmware errors under `/usr/lib/firmware/qcom/sm8150/Xiaomi/vayu/` |
| debos fails with KVM error | `ls -l /dev/kvm`; add user to group `kvm` or let it fall back to qemu |
| `Checksum mismatch` | Upstream archive changed → update hashes in `versions.env` |

Debug over USB: Mobian provides a USB network interface; with an SSH key built in
(`-s` / secret `SSH_AUTHORIZED_KEYS`) you can log in via `ssh mobian@10.66.0.1`.

## Credits

- [Mobian](https://mobian-project.org/) / [mobian-recipes](https://salsa.debian.org/Mobian-team/mobian-recipes) – build system
- [postmarketOS](https://postmarketos.org/) vayu port (Arseniy Velikanov, Ali Nasrullayev)
  – kernel config, patches, firmware packaging, ALSA UCM
- [sm8150-mainline](https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux) – kernel

The firmware is proprietary and only downloaded at build time; it is not part of this repository.
