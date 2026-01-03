# Common Configuration Tasks

Examples of common NiXOA configuration changes.

## Adding SSH Keys

Edit `~/user-config/configuration.nix`:

```nix
systemSettings.sshKeys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@laptop"
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@desktop"
];
```

Then apply:

```bash
cd ~/user-config
./scripts/apply-config "Added SSH keys"
```

To get your SSH public key:

```bash
# If you have SSH key already
cat ~/.ssh/id_ed25519.pub

# Generate new key if needed
ssh-keygen -t ed25519 -C "your@email.com"
cat ~/.ssh/id_ed25519.pub
```

## Enable NFS Storage

```nix
systemSettings.storage.nfs.enable = true;
```

Then apply:

```bash
./scripts/apply-config "Enabled NFS storage"
```

After deployment, mount storage in XO web interface.

## Enable CIFS/SMB Storage

```nix
systemSettings.storage.cifs.enable = true;
```

Then apply:

```bash
./scripts/apply-config "Enabled CIFS storage"
```

## Enable VHD Support

```nix
systemSettings.storage.vhd.enable = true;
```

## Enable Terminal Extras

Add developer tools and enhanced shell:

```nix
userSettings.extras.enable = true;
```

Includes:
- Zsh shell with Oh My Zsh
- Oh My Posh prompt
- fzf, ripgrep, fd, bat, eza
- lazygit, gh, and more

Apply:

```bash
./scripts/apply-config "Enabled terminal extras"
```

## Add User Packages

```nix
userSettings.packages.extra = [
  "neovim"
  "tmux"
  "lazygit"
  "ripgrep"
  "fd"
  "fzf"
  "bat"
];
```

Apply:

```bash
./scripts/apply-config "Added user packages"
```

To find package names, search at: https://search.nixos.org

## Add System Packages

```nix
systemSettings.packages.system.extra = [
  "htop"
  "git"
  "curl"
  "wget"
  "jq"
];
```

## Change XO Port

Default is port 80 for HTTP, 443 for HTTPS.

```nix
systemSettings.xo = {
  port = 8080;       # Custom HTTP port
  httpsPort = 8443;  # Custom HTTPS port
  tls.enable = true;
};
```

Then apply and update firewall if needed.

## Change Boot Loader

Switch between systemd-boot (default) and GRUB:

```nix
# For systemd-boot (modern, recommended)
systemSettings.boot.loader = "systemd-boot";

# For GRUB (legacy systems)
systemSettings.boot.loader = "grub";
```

## Enable Automated Updates

### NixPkgs Updates

Automatically update packages:

```nix
systemSettings.updates.nixpkgs = {
  enable = true;
  schedule = "Mon 04:00";
  keepGenerations = 7;
};
```

### Xen Orchestra Updates

Automatically update XO:

```nix
systemSettings.updates.xoa = {
  enable = true;
  schedule = "Tue 04:00";
  keepGenerations = 7;
};
```

## Configure Firewall

Allow additional ports:

```nix
systemSettings.networking.firewall.allowedTCPPorts = [
  22      # SSH (already default)
  80      # HTTP
  443     # HTTPS
  3389    # RDP
  5900    # VNC
  8012    # Custom service
];

systemSettings.networking.firewall.allowedUDPPorts = [
  # Add UDP ports if needed
];
```

## Disable Auto-Generated Certificates

To use your own certificates:

```nix
systemSettings.xo.tls = {
  enable = true;
  redirectToHttps = true;
  autoGenerate = false;  # Don't auto-generate
};
```

Then manually place certificates in `/etc/ssl/xo/`.

## Change Timezone

```nix
systemSettings.timezone = "America/New_York";
```

Other examples:
- `UTC`
- `Europe/London`
- `America/Los_Angeles`
- `Asia/Tokyo`
- `Australia/Sydney`

Full list in `/etc/zoneinfo/`

## Change Hostname

```nix
systemSettings.hostname = "my-new-hostname";
```

Apply and verify:

```bash
./scripts/apply-config "Changed hostname"
hostname   # Verify it changed
```

## Change Admin Username

⚠️ **Warning**: Only change before first deployment!

```nix
systemSettings.username = "custom-admin-user";
```

## Configure CIFS Storage Mount Credentials

In `config.nixoa.toml` (optional TOML overrides):

```toml
[cifs]
username = "your-cifs-user"
password = "your-cifs-password"
```

Or in pure Nix in `configuration.nix` if your system supports it.

## Configure NFS Mount Options

By default NFS uses sensible defaults (NFSv4/v3 auto-negotiation).

For custom NFS options, manually mount:

```bash
sudo mount -t nfs server.example.com:/export /var/lib/xo/mounts/nfs-server
```

## View All Applied Settings

After making changes:

```bash
cd ~/user-config
./scripts/show-diff      # See what changed
git log --oneline        # See all commits
git show <commit-hash>   # See details of specific commit
```

## Revert Recent Changes

```bash
cd ~/user-config

# See what commits exist
git log --oneline

# Revert to previous commit
git reset HEAD~1

# Or checkout specific file
git checkout HEAD~1 -- configuration.nix
```

## Apply and Test Without Switching

```bash
# Build but don't switch
sudo nixos-rebuild test --flake .#HOSTNAME

# Build but don't boot into it
sudo nixos-rebuild build --flake .#HOSTNAME
```

## Common Mistakes

### Syntax Errors in Nix

```bash
# Validate before applying
cd ~/user-config
nix flake check .
```

### Forgetting to Apply

Configuration changes require rebuild:

```bash
# Edit file
nano configuration.nix

# Apply changes (both commit and rebuild)
./scripts/apply-config "Description"

# Don't forget this step!
```

### Wrong Package Name

```bash
# Search for package
nix search nixpkgs <package-name>

# Example: looking for neovim
nix search nixpkgs neovim
```

### Changes Not Taking Effect

```bash
# Full rebuild with cache cleared
sudo nixos-rebuild switch --flake .#HOSTNAME --recreate-lock-file

# Or rollback if broken
sudo nixos-rebuild switch --rollback
```

## Need Help?

- See [Configuration Guide](./configuration.md) for complete option reference
- Check [Troubleshooting](./troubleshooting.md) if something breaks
- Visit [Issues](https://codeberg.org/nixoa/nixoa-vm/issues)
