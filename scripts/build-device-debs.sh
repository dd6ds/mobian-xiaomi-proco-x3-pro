#!/bin/bash
# Build the two small device packages:
#   firmware-xiaomi-vayu      - vendor firmware (DSPs, modem, GPU zap, WLAN, touch)
#   mobian-xiaomi-vayu-tweaks - ALSA UCM profile and other device config
set -euo pipefail
. "$(dirname "$0")/common.sh"

PKGDIR="${OUTDIR}/packages"
BUILD="${WORKDIR}/debs"
rm -rf "${BUILD}"; mkdir -p "${BUILD}" "${PKGDIR}"

# --------------------------------------------------------------------------
# firmware-xiaomi-vayu
# --------------------------------------------------------------------------
SUM=""
[ "${FIRMWARE_COMMIT}" = "${FIRMWARE_COMMIT_DEFAULT}" ] && SUM="${FIRMWARE_SHA512_DEFAULT}"
TARBALL="${DLDIR}/firmware-xiaomi-vayu-${FIRMWARE_COMMIT}.tar.gz"
download "${FIRMWARE_URL}" "${TARBALL}" "${SUM}"

tar -xzf "${TARBALL}" -C "${BUILD}"
FW_SRC="$(find "${BUILD}" -mindepth 1 -maxdepth 1 -type d -name 'firmware-xiaomi-vayu-*' | head -1)/lib/firmware"
FW="${BUILD}/firmware-root"
FWDST="${FW}/usr/lib/firmware"
QC_SRC="${FW_SRC}/qcom/sm8150/xiaomi/vayu"
QC_DST="${FWDST}/qcom/sm8150/Xiaomi/vayu"   # path referenced by the device tree

install -d "${QC_DST}" "${FWDST}/novatek" "${FWDST}/ath10k/WCN3990/hw1.0"
install -m644 "${QC_SRC}"/adsp* "${QC_SRC}"/cdsp* "${QC_SRC}"/modem* \
              "${QC_SRC}"/a640_zap.mbn "${QC_SRC}"/wlanmdsp.mbn "${QC_DST}/"
install -m644 "${FW_SRC}"/novatek/j20s_novatek_ts* "${FWDST}/novatek/"
# Vendor ath10k firmware: the linux-firmware version crashes on this device
# (see pmaports work item 3803). Installed via dpkg-divert, see preinst.
install -m644 "${FW_SRC}"/ath10k/WCN3990/hw1.0/board-2.bin \
              "${FW_SRC}"/ath10k/WCN3990/hw1.0/firmware-5.bin \
              "${FWDST}/ath10k/WCN3990/hw1.0/"

# initramfs-tools hook: touchscreen + GPU firmware must be available early
install -d "${FW}/usr/share/initramfs-tools/hooks"
cat > "${FW}/usr/share/initramfs-tools/hooks/xiaomi-vayu-firmware" <<'EOF'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0 ;; esac
. /usr/share/initramfs-tools/hook-functions
for f in /usr/lib/firmware/novatek/j20s_novatek_ts_fw01.bin \
         /usr/lib/firmware/novatek/j20s_novatek_ts_fw02.bin \
         /usr/lib/firmware/qcom/sm8150/Xiaomi/vayu/a640_zap.mbn \
         /usr/lib/firmware/qcom/a6[34]0_sqe.fw* \
         /usr/lib/firmware/qcom/a640_gmu.bin*; do
    [ -e "$f" ] && copy_file firmware "$f"
done
exit 0
EOF
chmod 755 "${FW}/usr/share/initramfs-tools/hooks/xiaomi-vayu-firmware"

install -d "${FW}/DEBIAN"
DIVERTS="/usr/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin /usr/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin"
cat > "${FW}/DEBIAN/control" <<EOF
Package: firmware-xiaomi-vayu
Version: ${FIRMWARE_COMMIT:0:7}-1
Architecture: all
Section: non-free-firmware/kernel
Priority: optional
Maintainer: mobian-vayu builder <noreply@localhost>
Depends: firmware-qcom-soc, firmware-atheros
Description: Proprietary firmware for the Xiaomi POCO X3 Pro (vayu)
 ADSP, CDSP, modem, Adreno 640 zap shader, WLAN DSP, Novatek touchscreen
 and vendor ath10k WCN3990 firmware. Source: ${FIRMWARE_URL}
EOF
cat > "${FW}/DEBIAN/preinst" <<EOF
#!/bin/sh
set -e
if [ "\$1" = install ] || [ "\$1" = upgrade ]; then
    for f in ${DIVERTS}; do
        dpkg-divert --package firmware-xiaomi-vayu --add --rename --divert "\$f.debian" "\$f"
    done
fi
EOF
cat > "${FW}/DEBIAN/postrm" <<EOF
#!/bin/sh
set -e
if [ "\$1" = remove ] || [ "\$1" = purge ] || [ "\$1" = abort-install ]; then
    for f in ${DIVERTS}; do
        dpkg-divert --package firmware-xiaomi-vayu --remove --rename --divert "\$f.debian" "\$f"
    done
fi
EOF
cat > "${FW}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ] && command -v update-initramfs >/dev/null; then
    update-initramfs -u -k all || true
fi
EOF
chmod 755 "${FW}"/DEBIAN/preinst "${FW}"/DEBIAN/postrm "${FW}"/DEBIAN/postinst

# --------------------------------------------------------------------------
# mobian-xiaomi-vayu-tweaks
# --------------------------------------------------------------------------
TW="${BUILD}/tweaks-root"
install -Dm644 "${TOPDIR}/device/ucm/HiFi.conf" "${TW}/usr/share/alsa/ucm2/Xiaomi/vayu/HiFi.conf"
install -Dm644 "${TOPDIR}/device/ucm/vayu.conf" \
    "${TW}/usr/share/alsa/ucm2/conf.d/sm8150/Xiaomi POCO X3 Pro.conf"
if [ -d "${TOPDIR}/device/rootfs" ]; then
    cp -a "${TOPDIR}/device/rootfs/." "${TW}/"
fi
install -d "${TW}/DEBIAN"
cat > "${TW}/DEBIAN/control" <<EOF
Package: mobian-xiaomi-vayu-tweaks
Version: 1.0-${BUILD_NUMBER:-1}
Architecture: all
Section: misc
Priority: optional
Maintainer: mobian-vayu builder <noreply@localhost>
Depends: alsa-ucm-conf, firmware-xiaomi-vayu
Description: Device configuration for the Xiaomi POCO X3 Pro (vayu) on Mobian
 ALSA UCM profile (from the postmarketOS device-xiaomi-vayu port).
EOF

rm -f "${PKGDIR}"/firmware-xiaomi-vayu_*.deb "${PKGDIR}"/mobian-xiaomi-vayu-tweaks_*.deb
dpkg-deb --root-owner-group -Zxz --build "${FW}" "${PKGDIR}" >/dev/null
dpkg-deb --root-owner-group -Zxz --build "${TW}" "${PKGDIR}" >/dev/null
ls -l "${PKGDIR}"

fix_owner "${WORKDIR}" "${OUTDIR}"
log "Device packages done"
