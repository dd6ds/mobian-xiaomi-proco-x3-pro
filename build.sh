#!/bin/bash
# Build a Mobian image for the Xiaomi POCO X3 Pro (vayu).
#
#   ./build.sh [options]
#
#   -e ENV      phosh (default) | plasma-mobile | lomiri
#   -u USER     default user            (default: mobian)
#   -p PASS     default password / PIN  (default: 1234)
#   -H NAME     hostname                (default: mobian-vayu)
#   -s FILE     authorized_keys file -> enable SSH with key login
#   -K          only build packages (kernel, firmware, tweaks)
#   -I          only build the image (re-use packages in out/packages)
#   -n          no Docker for the package build (needs a Debian/Ubuntu host with deps)
#   -h          help
#
# Results: out/packages/*.deb and out/images/mobian-vayu-*
set -euo pipefail
TOPDIR="$(cd "$(dirname "$0")" && pwd)"
cd "${TOPDIR}"
. scripts/common.sh

DO_PKGS=1; DO_IMAGE=1; PKG_DOCKER=1
while getopts "e:u:p:H:s:KInh" opt; do
    case "$opt" in
        e) export MOBIAN_ENV="$OPTARG" ;;
        u) export MOBIAN_USER="$OPTARG" ;;
        p) export MOBIAN_PASSWORD="$OPTARG" ;;
        H) export MOBIAN_HOSTNAME="$OPTARG" ;;
        s) SSH_PUBKEY="$(realpath "$OPTARG")"; export SSH_PUBKEY ;;
        K) DO_IMAGE=0 ;;
        I) DO_PKGS=0 ;;
        n) PKG_DOCKER=0 ;;
        h|*) sed -n '2,17p' "$0"; exit 0 ;;
    esac
done

case "${MOBIAN_ENV:-phosh}" in
    phosh|plasma-mobile|lomiri) ;;
    *) die "Unknown environment '${MOBIAN_ENV}'" ;;
esac

command -v docker >/dev/null || die "docker is required"

if [ "${DO_PKGS}" = "1" ]; then
    if [ "${PKG_DOCKER}" = "1" ]; then
        log "Building packages in ${KERNEL_BUILDER_IMAGE} container"
        docker run --rm -t \
            -v "${TOPDIR}:/src" -w /src \
            -e INSTALL_DEPS=1 -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
            -e KERNEL_TAG -e KERNEL_URL -e FIRMWARE_COMMIT -e FIRMWARE_URL -e BUILD_NUMBER \
            "${KERNEL_BUILDER_IMAGE}" \
            bash -c "scripts/build-kernel.sh && scripts/build-device-debs.sh"
    else
        scripts/build-kernel.sh
        scripts/build-device-debs.sh
    fi
fi

if [ "${DO_IMAGE}" = "1" ]; then
    scripts/build-image.sh
fi

log "All done."
[ "${DO_IMAGE}" = "1" ] && echo "Flash with:  cd out/images && ./flash.sh"
exit 0
