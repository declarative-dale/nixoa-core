<!-- SPDX-License-Identifier: Apache-2.0 -->
# Packer deployment

The repository can build and deploy NiXOA without installing Packer into a
profile or into the appliance:

```bash
git clone https://codeberg.org/NiXOA/core.git
cd core
nix run .#deploy-template -- \
  --host XCP_POOL_MASTER \
  --iso-sr "ISO library" \
  --sr "Local storage" \
  --network "VM network" \
  --export-network "VM network" \
  --template-name NiXOA \
  --memory-mb 4096 \
  --disk-size-mb 51200 \
  --operator-key ~/.ssh/id_ed25519.pub
```

Nix supplies Packer from pinned nixpkgs and builds the Vates XenServer plugin
at pinned version 0.11.4. Both live only in the caller's Nix store. Neither is
added to `nixosConfigurations.nixoa`.

The helper saves non-secret pool settings to the ignored
`packer/local.pkrvars.json`. It never writes the XCP-ng password. Set
`PKR_VAR_remote_password` for non-interactive use; otherwise the helper prompts
without echo.

## What the build does

1. Nix builds `packages.x86_64-linux.installer-iso` and copies the immutable
   result to the ignored `output/nixoa-installer.iso` artifact path.
2. Packer uploads that ISO to the selected ISO SR and creates one UEFI VM with
   one disk and a DHCP network.
3. The live installer requires explicit destructive confirmation, partitions
   only that single Packer disk, clones `core`, writes the operator key, and
   generates the hardware module.
4. `nixos-install` installs `.#nixoa`; the VM reboots twice while Packer verifies
   cloud-init, Xen guest integration, Redis, XO, TLS, and SSH.
5. The final provisioner restores key-only SSH, commits generated host policy,
   clears cloud-init and machine identity, removes SSH host keys, and lets the
   XenServer plugin mark the VM as a native template.

The installer is the only component that partitions a disk. The installed
appliance continues to use `host/hardware-configuration.nix` as its sole disk
and filesystem source.

## Clone validation

Create a VM from the template, attach a Xen Orchestra NoCloud config drive with
an SSH key for `nixoa`, and boot it. Then run:

```bash
sudo /home/nixoa/nixoa/packer/scripts/verify-clone.sh
```

The check requires a NoCloud datasource, new machine and SSH identities,
key-only SSH, healthy Redis/XO services, and a responding HTTPS endpoint.

The known `nixoa`/`nixoa` password exists only in the live installer and the
temporary Packer override. The sealing step locks it before the native template
is finalized.
