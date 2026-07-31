# Getting Started

NiXOA expects an installed x86_64 NixOS guest running on XCP-ng. The guest
should boot successfully and have:

- working networking
- `/etc/nixos/hardware-configuration.nix`
- Git and Nix with flakes available
- at least one operator SSH public key

Clone and bootstrap:

```bash
git clone https://codeberg.org/NiXOA/core.git /tmp/nixoa-bootstrap
cd /tmp/nixoa-bootstrap
sudo ./scripts/bootstrap.sh \
  --repo-dir /home/nixoa/nixoa \
  --ssh-key 'ssh-ed25519 AAAA... operator@example'
```

After the first switch, connect as the fixed operator:

```bash
ssh nixoa@<vm-address>
```

Then inspect and operate the appliance:

```bash
nxcli status
nxcli host show
nxcli xo logs
nixoa-menu
```

The XO UI is available at `https://<vm-address>/` by default. The initial
certificate is self-signed.

For a cautious configuration change:

```bash
nxcli diff
nxcli apply --dry-run
nxcli boot
sudo systemctl reboot
```

Every command uses `.#nixoa`; no target argument is needed or accepted.
