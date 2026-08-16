#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

DEVVM_NAME=${DEVVM_NAME:-devvm}
DEVVM_IMAGE=${DEVVM_IMAGE:-local/devvm:latest}
DEVVM_CPUS=${DEVVM_CPUS:-2}
DEVVM_MEMORY=${DEVVM_MEMORY:-2G}
DEVVM_DNS_DOMAIN=${DEVVM_DNS_DOMAIN:-machine}
DEVVM_SSH_USER=${DEVVM_SSH_USER:-$(id -un)}

log() {
    printf '%s\n' "==> $*"
}

die() {
    printf '%s\n' "error: $*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

machine_exists() {
    container machine ls -q 2>/dev/null | grep -Fqx "$DEVVM_NAME"
}

assert_home_mount_none() {
    inspect=$(container machine inspect "$DEVVM_NAME")
    printf '%s\n' "$inspect" | grep -Eq '"homeMount"[[:space:]]*:[[:space:]]*"none"' || {
        printf '%s\n' "error: machine '$DEVVM_NAME' does not have homeMount=none." >&2
        printf '%s\n' "Refusing to continue because the host home directory may be exposed." >&2
        printf '%s\n' "Inspect with: container machine inspect '$DEVVM_NAME'" >&2
        printf '%s\n' "To repair: container machine set -n '$DEVVM_NAME' home-mount=none" >&2
        printf '%s\n' "Then stop and restart the machine before running this script again." >&2
        exit 1
    }
}
