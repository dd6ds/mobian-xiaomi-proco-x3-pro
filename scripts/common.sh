#!/bin/bash
# Shared helpers, sourced by the other scripts.

TOPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${WORKDIR:-${TOPDIR}/work}"
OUTDIR="${OUTDIR:-${TOPDIR}/out}"
# shellcheck disable=SC2034  # used by the sourcing scripts
DLDIR="${WORKDIR}/dl"

# shellcheck source=../versions.env
. "${TOPDIR}/versions.env"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# download <url> <dest> [sha512]
download() {
    local url="$1" dest="$2" sum="${3:-}"
    mkdir -p "$(dirname "${dest}")"
    if [ ! -s "${dest}" ]; then
        log "Downloading ${url}"
        curl -fL --retry 3 -o "${dest}.part" "${url}"
        mv "${dest}.part" "${dest}"
    fi
    if [ -n "${sum}" ]; then
        echo "${sum}  ${dest}" | sha512sum -c - >/dev/null \
            || { rm -f "${dest}"; die "Checksum mismatch for ${dest}"; }
        log "Checksum OK: $(basename "${dest}")"
    else
        warn "No pinned checksum for $(basename "${dest}") (non-default version)"
    fi
}

# Give files created as root inside containers back to the calling user
fix_owner() {
    if [ -n "${HOST_UID:-}" ] && [ "$(id -u)" = "0" ]; then
        chown -R "${HOST_UID}:${HOST_GID:-${HOST_UID}}" "$@" 2>/dev/null || true
    fi
}
