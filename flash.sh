#!/bin/bash
# Flash a Mobian image to a Xiaomi POCO X3 Pro (vayu) via fastboot.
#
#   ./flash.sh [options] [IMAGE_DIR]
#
#   --panel huaxing|tianma   display panel variant (default: auto-detect / ask)
#   --detect-panel           only detect the panel via adb (Android/recovery running) and exit
#   --boot-only              only flash the boot image (e.g. to switch panel variant)
#   --keep-dtbo              do not erase the dtbo partition
#   --vbmeta FILE            also flash FILE to vbmeta with verification disabled
#   --no-reboot              do not reboot at the end
#   -y, --yes                do not ask for confirmation
#   -h, --help               this help
#
# IMAGE_DIR defaults to the directory of this script. It must contain the
# *.boot-vayu-<panel>.img and *.rootfs.img files, or the *.tar.xz archive.
#
# WARNING: this erases ALL data on the phone (userdata) and removes Android.
set -euo pipefail

PANEL=""; BOOT_ONLY=0; KEEP_DTBO=0; VBMETA=""; REBOOT=1; YES=0; DETECT_ONLY=0
IMGDIR="$(cd "$(dirname "$0")" && pwd)"

c_g='\033[1;32m'; c_y='\033[1;33m'; c_r='\033[1;31m'; c_0='\033[0m'
log()  { printf "${c_g}==>${c_0} %s\n" "$*"; }
warn() { printf "${c_y}WARN:${c_0} %s\n" "$*" >&2; }
die()  { printf "${c_r}ERROR:${c_0} %s\n" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --panel) PANEL="${2:-}"; shift ;;
        --detect-panel) DETECT_ONLY=1 ;;
        --boot-only) BOOT_ONLY=1 ;;
        --keep-dtbo) KEEP_DTBO=1 ;;
        --vbmeta) VBMETA="${2:-}"; shift ;;
        --no-reboot) REBOOT=0 ;;
        -y|--yes) YES=1 ;;
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        -*) die "Unknown option $1" ;;
        *) IMGDIR="$(cd "$1" && pwd)" ;;
    esac
    shift
done

# ---------------------------------------------------------------- panel detect
detect_panel() {
    command -v adb >/dev/null || return 1
    adb get-state >/dev/null 2>&1 || return 1
    local cmdline
    cmdline="$(adb shell cat /proc/cmdline 2>/dev/null || true)"
    case "${cmdline}" in
        *huaxing*|*j20s_42_02_0b*) echo huaxing ;;
        *tianma*|*j20s_36_02_0a*)  echo tianma ;;
        *) return 1 ;;
    esac
}

if [ "${DETECT_ONLY}" = "1" ]; then
    p="$(detect_panel)" || die "Could not detect the panel. Boot Android or a recovery (TWRP/OrangeFox) with adb enabled."
    echo "Detected panel: ${p}"
    exit 0
fi

command -v fastboot >/dev/null || die "fastboot not found (sudo apt install fastboot)"

if [ -z "${PANEL}" ]; then
    if p="$(detect_panel)"; then
        PANEL="$p"; log "Detected panel via adb: ${PANEL}"
        log "Rebooting to bootloader"
        adb reboot bootloader
    else
        echo "Which display panel does your phone have?"
        echo "  1) huaxing"
        echo "  2) tianma"
        echo "(Unknown? Boot Android, enable adb and run: ./flash.sh --detect-panel"
        echo " A wrong choice is harmless: the screen stays black, re-run with --boot-only --panel <other>.)"
        read -r -p "Choice [1/2]: " c
        case "$c" in 1|huaxing) PANEL=huaxing ;; 2|tianma) PANEL=tianma ;; *) die "Invalid choice" ;; esac
    fi
fi
case "${PANEL}" in huaxing|tianma) ;; *) die "Panel must be 'huaxing' or 'tianma'" ;; esac

# ---------------------------------------------------------------- find images
shopt -s nullglob
# shellcheck disable=SC2206  # $1 is a glob on purpose
find_one() { local a=("$IMGDIR"/$1); [ ${#a[@]} -gt 0 ] && ls -t "${a[@]}" | head -1; }

SUMS="$(find_one "*.sha256sums" || true)"
if [ -n "${SUMS}" ]; then
    (cd "${IMGDIR}" && sha256sum --quiet --ignore-missing -c "$(basename "${SUMS}")") \
        || die "Checksum verification failed"
fi

BOOT="$(find_one "*.boot-vayu-${PANEL}.img" || true)"
ROOTFS="$(find_one "*.rootfs.img" || true)"
if [ -z "${BOOT}" ] || { [ "${BOOT_ONLY}" = "0" ] && [ -z "${ROOTFS}" ]; }; then
    ARCHIVE="$(find_one "mobian-*.tar.xz" || true)"
    [ -n "${ARCHIVE}" ] || die "No images found in ${IMGDIR}"
    log "Extracting $(basename "${ARCHIVE}")"
    tar -xJf "${ARCHIVE}" -C "${IMGDIR}"
    BOOT="$(find_one "*.boot-vayu-${PANEL}.img" || true)"
    ROOTFS="$(find_one "*.rootfs.img" || true)"
fi
[ -n "${BOOT}" ] || die "Boot image for panel '${PANEL}' not found"
[ "${BOOT_ONLY}" = "1" ] || [ -n "${ROOTFS}" ] || die "rootfs image not found"

# ---------------------------------------------------------------- device check
log "Waiting for a device in fastboot mode (Vol- + Power)..."
for _ in $(seq 60); do
    fastboot devices | grep -q fastboot && break
    sleep 1
done
fastboot devices | grep -q fastboot || die "No fastboot device found"

PRODUCT="$(fastboot getvar product 2>&1 | awk '/^product:/ {print $2}')"
case "${PRODUCT}" in
    vayu|bhima) log "Device: ${PRODUCT}" ;;
    *) die "This is not a POCO X3 Pro (product='${PRODUCT}'). Aborting." ;;
esac
UNLOCKED="$(fastboot getvar unlocked 2>&1 | awk '/^unlocked:/ {print $2}')"
[ "${UNLOCKED}" = "yes" ] || warn "Bootloader does not report 'unlocked: yes' (got '${UNLOCKED}')"

echo
echo "  boot   <- $(basename "${BOOT}")"
[ "${BOOT_ONLY}" = "1" ] || echo "  userdata <- $(basename "${ROOTFS}")  (ALL DATA WILL BE ERASED)"
[ "${KEEP_DTBO}" = "1" ] || echo "  dtbo   <- erased (Android will not boot until you restore it)"
[ -z "${VBMETA}" ] || echo "  vbmeta <- $(basename "${VBMETA}") (verification disabled)"
echo
if [ "${YES}" = "0" ]; then
    read -r -p "Type 'yes' to continue: " ok
    [ "${ok}" = "yes" ] || die "Aborted"
fi

# ---------------------------------------------------------------- flash
if [ -n "${VBMETA}" ]; then
    fastboot --disable-verity --disable-verification flash vbmeta "${VBMETA}"
fi
[ "${KEEP_DTBO}" = "1" ] || fastboot erase dtbo
fastboot flash boot "${BOOT}"
if [ "${BOOT_ONLY}" = "0" ]; then
    fastboot flash userdata "${ROOTFS}"
fi
[ "${REBOOT}" = "1" ] && fastboot reboot

log "Done. First boot can take a minute or two. Default login: mobian / 1234"
