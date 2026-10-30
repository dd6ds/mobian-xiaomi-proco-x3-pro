#!/bin/bash
# Build the Mobian image for vayu with mobian-recipes (debos), using the
# "qcom-wip" device type and the packages from out/packages.
#
# Environment:
#   MOBIAN_ENV      phosh | plasma-mobile | lomiri         (default: phosh)
#   MOBIAN_USER     default user                           (default: mobian)
#   MOBIAN_PASSWORD default password / PIN                 (default: 1234)
#   MOBIAN_HOSTNAME hostname                               (default: mobian-vayu)
#   SSH_PUBKEY      path to an authorized_keys file -> enables SSH in the image
#   DEBOS_MEMORY    RAM for the debos VM                   (default: 6G)
#   USE_DOCKER      1 = run debos in the godebos/debos container (default: 1)
set -euo pipefail
. "$(dirname "$0")/common.sh"

MOBIAN_ENV="${MOBIAN_ENV:-phosh}"
MOBIAN_USER="${MOBIAN_USER:-mobian}"
MOBIAN_PASSWORD="${MOBIAN_PASSWORD:-1234}"
MOBIAN_HOSTNAME="${MOBIAN_HOSTNAME:-mobian-vayu}"
DEBOS_MEMORY="${DEBOS_MEMORY:-6G}"
USE_DOCKER="${USE_DOCKER:-1}"

ls "${OUTDIR}"/packages/linux-image-*.deb >/dev/null 2>&1 \
    || die "No kernel package in ${OUTDIR}/packages - run ./build.sh (or scripts/build-kernel.sh) first"

RECIPES="${WORKDIR}/mobian-recipes"
log "Preparing mobian-recipes @ ${MOBIAN_RECIPES_REF}"
if [ ! -d "${RECIPES}/.git" ]; then
    git clone -q "${MOBIAN_RECIPES_URL}" "${RECIPES}"
fi
git -C "${RECIPES}" fetch -q origin
git -C "${RECIPES}" checkout -q -f "${MOBIAN_RECIPES_REF}"
git -C "${RECIPES}" clean -q -fdx -e '*.tar.xz'   # keep cached rootfs tarballs

QCOM="${RECIPES}/devices/qcom"
cp "${TOPDIR}/config/vayu.toml" "${QCOM}/configs/wip.toml"
mkdir -p "${QCOM}/packages" "${QCOM}/droid-juicer"
rm -f "${QCOM}"/packages/*.deb
cp "${OUTDIR}"/packages/*.deb "${QCOM}/packages/"

# Install our local .debs with apt instead of plain dpkg so that their
# dependencies (firmware-qcom-soc, firmware-atheros, ...) are pulled in.
sed -i 's|command: dpkg -i /srv/\*.deb|command: sh -c "apt-get update \&\& apt-get install -y /srv/*.deb \&\& rm -f /srv/*.deb"|' \
    "${QCOM}/packages-base.yaml"
grep -q 'apt-get install -y /srv' "${QCOM}/packages-base.yaml" \
    || die "Could not patch packages-base.yaml (mobian-recipes layout changed?)"

BUILD_ARGS=(-t qcom-wip -e "${MOBIAN_ENV}" -u "${MOBIAN_USER}" -p "${MOBIAN_PASSWORD}"
            -H "${MOBIAN_HOSTNAME}" -m "${DEBOS_MEMORY}")
if [ -n "${SSH_PUBKEY:-}" ]; then
    [ -f "${SSH_PUBKEY}" ] || die "SSH_PUBKEY file not found: ${SSH_PUBKEY}"
    mkdir -p "${RECIPES}/overlays/ssh"
    cp "${SSH_PUBKEY}" "${RECIPES}/overlays/ssh/authorized_keys"
    BUILD_ARGS+=(-s)
fi

DEBOS_EXTRA=""
if [ ! -w /dev/kvm ]; then
    warn "/dev/kvm not available - falling back to slow qemu emulation (expect several hours)"
    DEBOS_EXTRA="--fakemachine-backend=qemu"
fi

log "Running debos (environment: ${MOBIAN_ENV})"
if [ "${USE_DOCKER}" = "1" ]; then
    DOCKER_ARGS=(run --rm --workdir /recipes
                 --mount "type=bind,source=${RECIPES},destination=/recipes"
                 --security-opt label=disable --entrypoint /bin/bash
                 -e "ARGS=${DEBOS_EXTRA}" -e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)")
    [ -w /dev/kvm ] && DOCKER_ARGS+=(--device /dev/kvm)
    docker pull -q "${DEBOS_IMAGE}" >/dev/null
    # shellcheck disable=SC2016
    docker "${DOCKER_ARGS[@]}" "${DEBOS_IMAGE}" -c '
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends yq jq android-sdk-libsparse-utils \
            parted bmap-tools xz-utils mkbootimg >/dev/null
        ./build.sh "$@"
        chown -R "${HOST_UID}:${HOST_GID}" /recipes
    ' build "${BUILD_ARGS[@]}"
else
    (cd "${RECIPES}" && ARGS="${DEBOS_EXTRA}" ./build.sh "${BUILD_ARGS[@]}")
fi

log "Collecting artifacts"
IMGDIR="${OUTDIR}/images"
mkdir -p "${IMGDIR}"
NAME="$(cd "${RECIPES}" && ls -t mobian-wip-"${MOBIAN_ENV}"-*.rootfs.img | head -1)"
NAME="${NAME%.rootfs.img}"
[ -n "${NAME}" ] || die "No image produced"
FINAL="mobian-vayu-${MOBIAN_ENV}-$(date +%Y%m%d)"
for f in "${RECIPES}/${NAME}".*; do
    base="$(basename "$f")"
    mv -f "$f" "${IMGDIR}/${base/${NAME}/${FINAL}}"
done
log "Compressing ${FINAL}.tar.xz"
(cd "${IMGDIR}" && XZ_OPT="-T0 -6" tar -cJf "${FINAL}.tar.xz" "${FINAL}".boot-*.img "${FINAL}".rootfs.img)
(cd "${IMGDIR}" && sha256sum "${FINAL}".*.img "${FINAL}".tar.xz > "${FINAL}.sha256sums")
cp "${TOPDIR}/flash.sh" "${IMGDIR}/"
ls -lh "${IMGDIR}"
fix_owner "${OUTDIR}"
log "Image done: ${IMGDIR}/${FINAL}.*"
