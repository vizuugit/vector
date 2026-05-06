# Phase-1 dev box bootstrap

Reproducible Debian 12 hardening for the Vector Phase-1 single-host deploy.
Source mandate: [VEC-11](/VEC/issues/VEC-11). Roadmap: [VEC-2 §6](/VEC/issues/VEC-2#document-plan).

## What this gives you

- Non-root admin user with key-only SSH and passwordless sudo
- sshd: no root login, no password auth, no agent/X11/TCP forwarding, AllowUsers limited
- UFW default-deny inbound; opens sshd + FiveM TCP/UDP (30120 by default)
- fail2ban watching sshd via systemd
- Unattended security upgrades (no auto-reboot — we own the reboot window)
- Kernel/network sysctl hardening + auditd + persistent journald
- chrony for time sync

Everything runs from `bootstrap.sh`. Re-running it converges to the same state.

## Provisioning checklist (Hetzner AX42)

1. Order an **AX42** (Ryzen 5 7600, 64GB DDR5 ECC, 2× 512GB / 1TB NVMe) in **Falkenstein (FSN1)** via Hetzner Robot. Fallback: AX41-NVMe equivalent at the time of order. **Hard cap €80/mo recurring.** Setup fee is a separate one-time line item.
2. Choose **Debian 12 (Bookworm) — minimal** in the install image picker.
3. Provide your **SSH public key** during install so the rescue/install never accepts a password.
4. Decline any paid DDoS / monitoring add-ons (Hetzner's bundled L3/L4 protection is sufficient for Phase 1).
5. Wait for the provisioning email, copy the IPv4, and confirm SSH-as-root works:
   `ssh root@<ip>`
6. Run the bootstrap (see below). It will lock down root and switch to the admin user.

## Running the bootstrap

```sh
# 1. Copy the script up (from your workstation)
scp ops/bootstrap/bootstrap.sh root@<ip>:/root/bootstrap.sh

# 2. SSH in
ssh root@<ip>

# 3. Run it
chmod +x /root/bootstrap.sh
ADMIN_USER=cto \
ADMIN_SSH_PUBKEY="ssh-ed25519 AAAA... cto@vector" \
SSH_PORT=2200 \
FIVEM_TCP_PORTS=30120 \
FIVEM_UDP_PORTS=30120 \
/root/bootstrap.sh

# 4. From your workstation, verify the admin user works on the new port
ssh -p 2200 cto@<ip> 'sudo -n true && echo ok'

# 5. Only after #4 succeeds, close the root window
ssh -p 2200 cto@<ip> 'sudo passwd -l root'
```

> **Do not close your root SSH session until step 4 succeeds in a separate
> terminal.** If the admin user can't get in, you need root to fix it.

## Verifying reproducibility

Re-run the script on a freshly imaged box with the same env. Diff the
critical state to the first run:

```sh
diff -u box-a.state box-b.state
```

where each `state` file is collected with:

```sh
{
  ufw status numbered
  sshd -T | sort
  systemctl is-enabled fail2ban unattended-upgrades chrony auditd
  sysctl --system 2>/dev/null
  ls -l /etc/sudoers.d/10-admin
} > /tmp/state
```

A passing reproducibility test is: identical output across two clean runs.

## Future stages (not in this script)

- `ops/bootstrap/fivem.sh` — installs the FiveM artifact server, txAdmin, MariaDB, Redis (next ticket)
- `ops/bootstrap/backups.sh` — installs the rclone S3 backup job (next ticket)

This script intentionally stops at base hardening so it stays small, fast,
and re-runnable on any future box.
