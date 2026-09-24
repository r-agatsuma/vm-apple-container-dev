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
    machine_names=$(container machine ls -q) || die "could not list machines"
    printf '%s\n' "$machine_names" | grep -Fqx "$DEVVM_NAME"
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

ensure_container_services() {
    if ! container system status >/dev/null 2>&1; then
        log "starting Apple container services"
        container system start
    fi
}

ensure_dns_domain() {
    if ! container system dns ls -q 2>/dev/null | grep -Fqx "$DEVVM_DNS_DOMAIN"; then
        require_cmd sudo
        log "creating local DNS domain '$DEVVM_DNS_DOMAIN' (sudo required)"
        sudo container system dns create "$DEVVM_DNS_DOMAIN"
    fi
}

validate_ssh() {
    log "checking sshd"
    container machine run -n "$DEVVM_NAME" -- systemctl is-active --quiet ssh
    ssh_config=$(container machine run -n "$DEVVM_NAME" --root -- /usr/sbin/sshd -T)
    for setting in \
        'pubkeyauthentication yes' \
        'authenticationmethods publickey' \
        'passwordauthentication no' \
        'kbdinteractiveauthentication no' \
        'permitemptypasswords no' \
        'permitrootlogin no' \
        'usedns no' \
        'gssapiauthentication no'; do
        printf '%s\n' "$ssh_config" | grep -Fqx "$setting" || die "SSH policy mismatch: expected '$setting'"
        printf '%s\n' "$setting"
    done
}

print_connection_info() {
    printf '\nReady.\n'
    printf '\nOpenSSH config (add manually to ~/.ssh/config):\n'
    printf 'Host %s.%s\n    HostName %s.%s\n    User %s\n' \
        "$DEVVM_NAME" "$DEVVM_DNS_DOMAIN" "$DEVVM_NAME" "$DEVVM_DNS_DOMAIN" "$DEVVM_SSH_USER"
    printf '\nFor a non-default private-key filename, manually add the appropriate entry to this Host block, for example:\n'
    printf '    IdentityFile ~/.ssh/<private-key>\n'
    printf 'Private-key selection and ssh-agent configuration are your responsibility.\n'
    printf '\nAfter configuring SSH, connect with:\n  ssh %s.%s\n' "$DEVVM_NAME" "$DEVVM_DNS_DOMAIN"
}
