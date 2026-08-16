# apple-devvm

A small, persistent Linux development VM built from an OCI image and run with Apple `container machine`.

The repository deliberately treats `container machine` as a lightweight VM, not as an ephemeral application container.

## Security defaults

- macOS home-directory sharing is disabled with `--home-mount none`.
- SSH accepts public-key authentication only.
- Password and keyboard-interactive SSH authentication are disabled.
- Root SSH login is disabled.
- Host SSH private keys are never copied into the VM.
- On first build, `~/.ssh/id_*.pub` is copied into the image as `/etc/skel/.ssh/authorized_keys`; private keys are never included.
- SSH host private keys are generated per machine on first boot; they are not baked into the OCI image.
- The guest filesystem is persistent. Credentials created by tools such as Codex can therefore remain inside the VM until the machine is destroyed.

`container machine rm` deletes that persistent machine state.

## Prerequisites

- Apple silicon Mac supported by Apple `container`
- Apple `container` installed and initialized
- Rosetta 2 if your local `container` setup requires it
- At least one public key matching `~/.ssh/id_*.pub`

The scripts use the current Apple `container machine` CLI, including `--home-mount none` and the local DNS service.

## Quick start

```sh
git clone <this-repository>
cd apple-devvm

./scripts/up
./scripts/ssh
```

The first `up` does the following:

1. Starts Apple `container` services if necessary.
2. Creates the local `.machine` DNS domain if necessary. This step uses `sudo`.
3. Builds `local/devvm:latest` from the Dockerfile.
4. Creates a persistent machine named `devvm` with 2 CPUs, 2 GiB RAM, and host home sharing disabled.
5. Collects `~/.ssh/id_*.pub` into a temporary build input and bakes it into `/etc/skel/.ssh/authorized_keys`. Apple container machine copies `/etc/skel` into the new Linux user's home on first boot.
6. Verifies that `sshd` is active and key-only authentication is configured.

Later `up` runs reuse the existing persistent machine; they do not rebuild or replace its root filesystem. If the Dockerfile or authorized key set changes, recreate the machine with `./scripts/destroy` followed by `./scripts/up` to apply the new image. That intentionally discards machine-local state.

The default key selection is intentionally simple: `~/.ssh/id_*.pub`. If you want a different public key set, edit that glob in `scripts/up`.

After that:

```sh
ssh "$USER@devvm.machine"
```

or simply:

```sh
./scripts/ssh
```

## Lifecycle

```sh
./scripts/status
./scripts/stop
./scripts/up
./scripts/destroy
```

`stop` preserves the VM filesystem. `destroy` asks for confirmation, then removes the machine and its persistent state. It intentionally does not remove the OCI image or the shared `.machine` DNS domain.

## Configuration

Environment variables can override the small set of machine defaults:

```sh
DEVVM_NAME=mydev \
DEVVM_CPUS=4 \
DEVVM_MEMORY=4G \
./scripts/up
```

Available variables:

- `DEVVM_NAME` — default: `devvm`
- `DEVVM_IMAGE` — default: `local/devvm:latest`
- `DEVVM_CPUS` — default: `2`
- `DEVVM_MEMORY` — default: `2G`
- `DEVVM_DNS_DOMAIN` — default: `machine`
- `DEVVM_SSH_USER` — default: current macOS username

If a machine with the selected name already exists, `up` refuses to continue unless `container machine inspect` reports `homeMount: none`.

## Intended state split

The OCI image contains reproducible development-system state: packages, systemd, OpenSSH configuration, and common tools.

The machine filesystem contains user-specific persistent state: cloned repositories, shell history, caches, tool logins, and similar workstation data.

The macOS home directory is not mounted into the machine.
