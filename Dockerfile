FROM ubuntu:24.04

ENV container=container

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        dbus \
        git \
        iproute2 \
        iputils-ping \
        less \
        openssh-server \
        sudo \
        systemd \
        systemd-sysv \
        vim-tiny \
        wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Apple container machine copies /etc/skel into the host-matching user's home
# on first boot. Public keys are prepared by scripts/up before image build.
RUN mkdir -p /etc/skel/.ssh \
    && chmod 0700 /etc/skel/.ssh
COPY .authorized_keys /etc/skel/.ssh/authorized_keys
RUN chmod 0600 /etc/skel/.ssh/authorized_keys

# Apple container machine provisions a host-matching user on first boot.
# Inside the VM that user may sudo without a password; SSH itself is key-only.
RUN printf '%s\n' 'ALL ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/devvm \
    && chmod 0440 /etc/sudoers.d/devvm

# A cloned machine needs a fresh machine-id.
RUN : > /etc/machine-id \
    && : > /var/lib/dbus/machine-id

RUN systemctl set-default multi-user.target \
    && systemctl mask \
        dev-hugepages.mount \
        sys-fs-fuse-connections.mount \
        systemd-update-utmp.service \
        systemd-tmpfiles-setup.service \
        console-getty.service \
    && systemctl disable networkd-dispatcher.service || true

# SSH policy: public-key only, no root login.
RUN mkdir -p /etc/ssh/sshd_config.d /run/sshd \
    && printf '%s\n' \
        'PubkeyAuthentication yes' \
        'AuthenticationMethods publickey' \
        'PasswordAuthentication no' \
        'KbdInteractiveAuthentication no' \
        'ChallengeResponseAuthentication no' \
        'PermitEmptyPasswords no' \
        'PermitRootLogin no' \
        'UseDNS no' \
        'GSSAPIAuthentication no' \
        > /etc/ssh/sshd_config.d/99-devvm.conf \
    && /usr/sbin/sshd -t \
    && systemctl enable ssh

# Do not bake SSH host private keys into the OCI image. Generate unique keys
# in each persistent machine on first boot instead.
RUN rm -f /etc/ssh/ssh_host_* \
    && printf '%s\n' \
        '[Unit]' \
        'Description=Generate SSH host keys for devvm' \
        'Before=ssh.service' \
        '' \
        '[Service]' \
        'Type=oneshot' \
        'ExecStart=/usr/bin/ssh-keygen -A' \
        'RemainAfterExit=yes' \
        > /etc/systemd/system/devvm-ssh-hostkeys.service \
    && mkdir -p /etc/systemd/system/ssh.service.d \
    && printf '%s\n' \
        '[Unit]' \
        'Requires=devvm-ssh-hostkeys.service' \
        'After=devvm-ssh-hostkeys.service' \
        > /etc/systemd/system/ssh.service.d/10-devvm-hostkeys.conf

EXPOSE 22
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
