# Installation

## Prepare the VM

Create an x86_64 VM in XCP-ng, install NixOS normally, and verify that it boots.
Partitioning is deliberately outside this repository. NiXOA never assumes
`/dev/xvda*`, never repartitions the guest, and never replaces generated
filesystem declarations.

Keep `/etc/nixos/hardware-configuration.nix` from the installed VM. Bootstrap
copies it to `host/hardware-configuration.nix`.

## Run bootstrap

```bash
sudo ./scripts/bootstrap.sh \
  --repo-dir /home/nixoa/nixoa \
  --timezone America/Chicago \
  --ssh-key 'ssh-ed25519 AAAA... operator@example'
```

Useful options:

- `--repo-url URL` and `--branch NAME`: choose the checkout source
- `--git-name` and `--git-email`: set operator commit identity
- `--ssh-key KEY`: repeat for multiple keys
- `--enable-flakes`: persist flake support before validation
- `--skip-check`: skip pre-switch flake validation
- `--skip-hardware-copy`: retain the repository placeholder for test workflows
- `--no-first-switch`: configure and validate without activation

Hostname, username, platform, and profile options do not exist. They are fixed
to `nixoa`, `nixoa`, `x86_64-linux`, and XCP-ng guest respectively.

## What bootstrap changes

Bootstrap:

1. clones or fast-forwards the repository
2. writes `host/settings.nix`
3. populates the `nixoa` SSH key list
4. copies the generated hardware module
5. stages the fixed host files so flake evaluation can see them
6. runs `nix flake check --no-write-lock-file`
7. switches to `.#nixoa`, unless disabled
8. hands the checkout to the `nixoa` operator

The first switch removes SSH access for the installer `nixos` account.
Confirm the supplied public key is correct before activation.

## Validate after installation

```bash
nxcli status
systemctl status xen-guest-agent.service
systemctl status redis-xo.service
systemctl status xo-server.service
curl --insecure https://localhost/
```
