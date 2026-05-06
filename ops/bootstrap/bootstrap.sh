#!/usr/bin/env bash
# Vector Phase-1 dev box bootstrap — Debian 12 hardening.
#
# Idempotent: re-running on the same box must converge to the same state.
# Source mandate: VEC-11.
#
# Run as root on a fresh Debian 12 install. Required env:
#   ADMIN_USER          — non-root sudo account to create (e.g. cto)
#   ADMIN_SSH_PUBKEY    — single SSH public key line authorized for ADMIN_USER
#   SSH_PORT            — sshd listen port (default 22; 2200 recommended)
#   FIVEM_TCP_PORTS     — comma-separated TCP ports to allow (default "30120")
#   FIVEM_UDP_PORTS     — comma-separated UDP ports to allow (default "30120")
#
# Verify reproducibility by re-running on a fresh box and diffing /etc state.

set -Eeuo pipefail

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "bootstrap.sh must run as root" >&2
        exit 1
    fi
}

require_env() {
    local missing=()
    for var in ADMIN_USER ADMIN_SSH_PUBKEY; do
        if [[ -z "${!var:-}" ]]; then missing+=("$var"); fi
    done
    if (( ${#missing[@]} )); then
        echo "missing required env: ${missing[*]}" >&2
        exit 1
    fi
}

apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends "$@"
}

stage_apt() {
    echo ">> apt update + base packages"
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
    apt_install \
        ca-certificates curl gnupg lsb-release \
        ufw fail2ban unattended-upgrades apt-listchanges \
        sudo openssh-server \
        htop iotop iftop \
        rsync git jq \
        chrony \
        auditd
}

stage_unattended_upgrades() {
    echo ">> unattended security upgrades"
    cat >/etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CONF
    cat >/etc/apt/apt.conf.d/50unattended-upgrades <<'CONF'
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian";
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::SyslogEnable "true";
CONF
    systemctl enable --now unattended-upgrades.service
}

stage_admin_user() {
    echo ">> admin user: $ADMIN_USER"
    if ! id -u "$ADMIN_USER" >/dev/null 2>&1; then
        useradd --create-home --shell /bin/bash --groups sudo "$ADMIN_USER"
    fi
    usermod -aG sudo "$ADMIN_USER"
    passwd -l "$ADMIN_USER"  # disable password auth, key only

    local ssh_dir="/home/$ADMIN_USER/.ssh"
    install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$ssh_dir"
    local auth="$ssh_dir/authorized_keys"
    # Replace the file each run so removed keys are revoked. Keep ownership tight.
    printf '%s\n' "$ADMIN_SSH_PUBKEY" > "$auth"
    chown "$ADMIN_USER:$ADMIN_USER" "$auth"
    chmod 600 "$auth"

    # Passwordless sudo for the admin user (key-only, no shared secret).
    cat >/etc/sudoers.d/10-admin <<SUDO
$ADMIN_USER ALL=(ALL) NOPASSWD:ALL
Defaults:$ADMIN_USER !requiretty
SUDO
    chmod 440 /etc/sudoers.d/10-admin
    visudo -cf /etc/sudoers.d/10-admin
}

stage_sshd() {
    echo ">> sshd hardening"
    local port="${SSH_PORT:-22}"
    install -d -m 755 /etc/ssh/sshd_config.d
    cat >/etc/ssh/sshd_config.d/10-vector.conf <<CONF
# Managed by ops/bootstrap/bootstrap.sh — do not edit by hand.
Port $port
AddressFamily any
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
LoginGraceTime 30
AllowUsers $ADMIN_USER
CONF
    sshd -t
    systemctl restart ssh
}

stage_firewall() {
    echo ">> ufw default-deny + allow lists"
    local ssh_port="${SSH_PORT:-22}"
    local fivem_tcp="${FIVEM_TCP_PORTS:-30120}"
    local fivem_udp="${FIVEM_UDP_PORTS:-30120}"

    ufw --force reset >/dev/null
    ufw default deny incoming
    ufw default allow outgoing
    ufw limit "$ssh_port"/tcp comment 'sshd'

    IFS=',' read -r -a tcp <<< "$fivem_tcp"
    for p in "${tcp[@]}"; do ufw allow "$p"/tcp comment 'fivem'; done
    IFS=',' read -r -a udp <<< "$fivem_udp"
    for p in "${udp[@]}"; do ufw allow "$p"/udp comment 'fivem'; done

    ufw --force enable
    ufw status verbose
}

stage_fail2ban() {
    echo ">> fail2ban for sshd"
    local port="${SSH_PORT:-22}"
    cat >/etc/fail2ban/jail.d/sshd.local <<CONF
[sshd]
enabled = true
port    = $port
backend = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
CONF
    systemctl enable --now fail2ban
    systemctl restart fail2ban
}

stage_kernel_sysctl() {
    echo ">> sysctl network/kernel hardening"
    cat >/etc/sysctl.d/99-vector.conf <<'CONF'
# Network hardening
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.tcp_syncookies=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0

# Kernel hardening
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.unprivileged_bpf_disabled=1
fs.protected_hardlinks=1
fs.protected_symlinks=1
fs.protected_fifos=2
fs.protected_regular=2
CONF
    sysctl --system >/dev/null
}

stage_time_sync() {
    echo ">> chrony"
    systemctl enable --now chrony
}

stage_audit() {
    echo ">> auditd"
    systemctl enable --now auditd
}

stage_journal() {
    echo ">> journald persistence"
    install -d /var/log/journal
    systemd-tmpfiles --create --prefix /var/log/journal
    sed -i \
        -e 's/^#\?Storage=.*/Storage=persistent/' \
        -e 's/^#\?SystemMaxUse=.*/SystemMaxUse=1G/' \
        /etc/systemd/journald.conf
    systemctl restart systemd-journald
}

stage_summary() {
    echo
    echo "=== bootstrap complete ==="
    echo "admin user: $ADMIN_USER (sudo, key-only)"
    echo "sshd port:  ${SSH_PORT:-22}"
    echo "ufw:"
    ufw status numbered | sed 's/^/  /'
    echo
    echo "Verify from your workstation:"
    echo "  ssh -p ${SSH_PORT:-22} $ADMIN_USER@<box-ip>"
}

main() {
    require_root
    require_env
    stage_apt
    stage_unattended_upgrades
    stage_admin_user
    stage_sshd
    stage_firewall
    stage_fail2ban
    stage_kernel_sysctl
    stage_time_sync
    stage_audit
    stage_journal
    stage_summary
}

main "$@"
