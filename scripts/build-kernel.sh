#!/bin/bash
# Build the mainline SM8150 kernel for vayu as a Debian package (linux-image-*.deb).
# Runs on Debian/Ubuntu (natively or in a container). Cross-compiles with clang.
set -euo pipefail
. "$(dirname "$0")/common.sh"

if [ "${INSTALL_DEPS:-0}" = "1" ]; then
    log "Installing kernel build dependencies"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
        build-essential bc bison flex cpio kmod rsync python3 perl \
        libssl-dev libelf-dev dpkg-dev debhelper curl ca-certificates xz-utils \
        clang lld llvm gcc-aarch64-linux-gnu libc6-dev-arm64-cross patch >/dev/null
fi

SRCDIR="${WORKDIR}/kernel/linux-${KERNEL_TAG}"
TARBALL="${DLDIR}/linux-${KERNEL_TAG}.tar.gz"

SUM=""
[ "${KERNEL_TAG}" = "${KERNEL_TAG_DEFAULT}" ] && SUM="${KERNEL_SHA512_DEFAULT}"
download "${KERNEL_URL}" "${TARBALL}" "${SUM}"

log "Extracting kernel ${KERNEL_TAG}"
rm -rf "${WORKDIR}/kernel"
mkdir -p "${WORKDIR}/kernel"
tar -xzf "${TARBALL}" -C "${WORKDIR}/kernel"
[ -d "${SRCDIR}" ] || SRCDIR="$(find "${WORKDIR}/kernel" -mindepth 1 -maxdepth 1 -type d | head -1)"
cd "${SRCDIR}"

for p in "${TOPDIR}"/kernel/patches/*.patch; do
    [ -e "$p" ] || continue
    log "Applying $(basename "$p")"
    patch -p1 --forward --no-backup-if-mismatch < "$p" \
        || warn "Patch $(basename "$p") did not apply cleanly (already upstream?)"
done

MAKE=(make ARCH=arm64 LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)")

log "Configuring kernel"
cp "${TOPDIR}/kernel/config-sm8150.aarch64" .config
ARCH=arm64 LLVM=1 ./scripts/kconfig/merge_config.sh -m .config "${TOPDIR}/kernel/mobian-vayu.config"
"${MAKE[@]}" olddefconfig
grep -q '^CONFIG_EFI_ZBOOT=y' .config && die "EFI_ZBOOT is still enabled"

if [ "${KERNEL_CONFIG_ONLY:-0}" = "1" ]; then
    fix_owner "${WORKDIR}"
    log "Config only: ${SRCDIR}/.config"; exit 0
fi

KREL="$("${MAKE[@]}" -s kernelrelease)"
PKGVER="${KREL}-${BUILD_NUMBER:-1}"
log "Building linux-image-${KREL} (${PKGVER})"

# Only the image package is needed (no headers / debug packages)
export DEB_BUILD_PROFILES="pkg.linux-upstream.nokernelheaders pkg.linux-upstream.nokerneldbg"
"${MAKE[@]}" KBUILD_DEBARCH=arm64 KDEB_PKGVERSION="${PKGVER}" \
    KBUILD_BUILD_USER=mobian-vayu KBUILD_BUILD_HOST=builder bindeb-pkg

mkdir -p "${OUTDIR}/packages"
rm -f "${OUTDIR}"/packages/linux-image-*.deb
cp "${WORKDIR}"/kernel/linux-image-"${KREL}"_*.deb "${OUTDIR}/packages/"
ls -l "${OUTDIR}"/packages/linux-image-*.deb

# Sanity check: both DTBs must be in the package
dpkg-deb -c "${OUTDIR}"/packages/linux-image-*.deb | grep -E 'sm8150-xiaomi-vayu-(huaxing|tianma)\.dtb' \
    || die "vayu DTBs missing from kernel package"

fix_owner "${WORKDIR}" "${OUTDIR}"
log "Kernel package done"
