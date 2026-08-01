# Installation

## Deploy a native template with Packer

The preferred fresh deployment starts from a repository checkout and requires
only Nix plus access to the XCP-ng pool master:

```bash
nix run --accept-flake-config .#deploy-template -- \
  --host XCP_POOL_MASTER \
  --iso-sr "ISO library" \
  --sr "Local storage" \
  --network "DHCP network" \
  --export-network "DHCP network" \
  --template-name NiXOA \
  --operator-key ~/.ssh/id_ed25519.pub
```

The flake app realizes Packer from pinned nixpkgs and the pinned Vates
XenServer plugin in the caller's Nix store. It does not install either tool
into the caller's profile or `nixosConfigurations.nixoa`.

By default, the deployment helper uses GitHub CLI to download the
`nixoa-installer` artifact from the newest successful `main` installer workflow
into a temporary directory. It verifies the artifact's published SHA-256 file
and gives the ISO path directly to Packer. Run `gh auth login` before the first
deployment. The temporary download is removed when Packer exits.

The Nix binary caches and signing keys are declared directly in `flake.nix` and
accepted by the command above. The large GitHub Actions artifact is not a flake
input and is not recorded in `flake.lock`; it is a deployment-time transport
for the closure-preseeded ISO. A newly pushed checkout can therefore use the
preceding successful artifact until its own workflow completes. Set
`INSTALLER_SOURCE=build` to build the current checkout's `installer-iso` output
locally, or `INSTALLER_ISO=/path/to/image.iso` to select an exact image.

The helper stores only non-secret settings in ignored
`packer/local.pkrvars.json`. Supply `PKR_VAR_remote_password` for unattended
execution or enter the password at its hidden prompt.

The resulting object is a native XCP-ng template. Clone it in Xen Orchestra,
enable the NoCloud config drive, supply an SSH public key for `nixoa`, and boot.
Every clone generates fresh machine and SSH identities. See
`packer/README.md` for the full build and verification contract.

The Packer installer intentionally erases its one selected build disk. This is
separate from clone runtime policy: NixOS continues to own the generated
filesystem declarations, while cloud-init may extend only the existing root
partition and filesystem when the clone's virtual disk is larger.

## Bootstrap an existing NixOS VM

## Prepare the VM

Create an x86_64 VM in XCP-ng, install NixOS normally, and verify that it boots.
Partitioning is deliberately outside this bootstrap path. Bootstrap never
assumes `/dev/xvda*`, repartitions the guest, or replaces generated filesystem
declarations.

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
