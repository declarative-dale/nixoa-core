# Configuration Guide

Understand all the configuration options available in NiXOA.

## Configuration Location

All configuration happens in `~/user-config/configuration.nix` using pure Nix syntax.

## Basic Structure

```nix
{ lib, pkgs, ... }:

{
  userSettings = {
    # User environment configuration
  };

  systemSettings = {
    # System-wide configuration
  };
}
```

## System Settings

### Basic Identification

```nix
systemSettings = {
  hostname = "my-nixoa";           # System hostname
  username = "xoa";                # Admin user
  stateVersion = "25.11";          # NixOS version (don't change)
  timezone = "UTC";                # Timezone
  sshKeys = [                       # Your SSH public keys
    "ssh-ed25519 AAAAC3..."
  ];
};
```

**Timezones:** UTC, America/New_York, Europe/London, etc.
See `/etc/zoneinfo/` for full list.

### Xen Orchestra Service

```nix
xo = {
  port = 80;                        # HTTP port
  httpsPort = 443;                  # HTTPS port

  tls = {
    enable = true;                  # Use HTTPS
    redirectToHttps = true;         # Redirect HTTP→HTTPS
    autoGenerate = true;            # Auto-generate self-signed certs
  };

  service = {
    user = "xo";                    # Service user
    group = "xo";                   # Service group
  };

  host = "0.0.0.0";                 # Bind address
};
```

### Storage Support

Enable remote storage backends:

```nix
storage = {
  nfs.enable = true;                # NFS mounts
  cifs.enable = true;               # CIFS/SMB mounts
  vhd.enable = true;                # VHD/VHDX support
  mountsDir = "/var/lib/xo/mounts"; # Mount directory
};
```

### Networking

```nix
networking = {
  firewall.allowedTCPPorts = [
    22    # SSH
    80    # HTTP
    443   # HTTPS
    3389  # RDP
    5900  # VNC
    8012  # Some services
  ];

  firewall.allowedUDPPorts = [];
};
```

### System Packages

```nix
packages.system.extra = [
  "htop"
  "git"
  "vim"
  "curl"
];
```

### Boot Configuration

```nix
boot = {
  loader = "systemd-boot";  # or "grub" for legacy systems
};
```

### Automated Updates

```nix
updates = {
  gc = {
    enable = true;
    schedule = "Sun 04:00";       # Sunday 4 AM
    keepGenerations = 7;          # Keep 7 generations
  };

  nixpkgs = {
    enable = true;
    schedule = "Mon 04:00";       # Monday 4 AM
    keepGenerations = 7;
  };

  xoa = {
    enable = true;
    schedule = "Tue 04:00";       # Tuesday 4 AM
    keepGenerations = 7;
  };
};
```

### Notification Settings (Optional)

```nix
# Add within updates section for notifications
monitoring = {
  ntfy = {
    enable = true;
    server = "https://ntfy.sh";
    topic = "my-xoa-updates";
  };
};
```

## User Settings

### Packages

Add packages for your user (via Home Manager):

```nix
userSettings = {
  packages.extra = [
    "neovim"
    "tmux"
    "lazygit"
    "ripgrep"
    "fzf"
  ];
};
```

### Terminal Extras

Enable enhanced terminal experience:

```nix
userSettings = {
  extras.enable = true;  # Enables zsh, oh-my-posh, tools
};
```

Includes:
- Zsh shell with Oh My Zsh
- Oh My Posh prompt (Darcula theme)
- Tools: fzf, ripgrep, fd, bat, eza, and more
- Developer utilities: lazygit, gh, bottom

## Full Example Configuration

```nix
{ lib, pkgs, ... }:

{
  userSettings = {
    packages.extra = [
      "neovim"
      "tmux"
      "lazygit"
    ];
    extras.enable = true;  # Enhanced terminal
  };

  systemSettings = {
    # Basic identification
    hostname = "my-xoa";
    username = "xoa";
    timezone = "America/New_York";
    stateVersion = "25.11";
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... user@laptop"
    ];

    # Xen Orchestra
    xo = {
      port = 80;
      httpsPort = 443;
      tls = {
        enable = true;
        redirectToHttps = true;
        autoGenerate = true;
      };
    };

    # Storage
    storage = {
      nfs.enable = true;
      cifs.enable = true;
      vhd.enable = true;
      mountsDir = "/var/lib/xo/mounts";
    };

    # Networking
    networking.firewall.allowedTCPPorts = [
      22 80 443
    ];

    # Boot
    boot.loader = "systemd-boot";

    # System packages
    packages.system.extra = [
      "htop"
      "git"
    ];

    # Automated updates
    updates = {
      gc = {
        enable = true;
        schedule = "Sun 04:00";
      };
      nixpkgs = {
        enable = true;
        schedule = "Mon 04:00";
      };
      xoa = {
        enable = true;
        schedule = "Tue 04:00";
      };
    };
  };
}
```

## Optional: TOML Overrides

For some settings, you can also use `config.nixoa.toml` (optional):

```toml
[redis]
socket = "/run/redis-xo/redis.sock"

[logs]
level = "info"  # trace, debug, info, warn, error

[authentication]
defaultTokenValidity = "30 days"
```

## Applying Changes

After editing `configuration.nix`:

```bash
cd ~/user-config
./scripts/apply-config "Updated configuration"
```

This commits your changes and rebuilds the system.

## Common Configuration Tasks

See [Common Tasks](./common-tasks.md) for examples of:
- Adding SSH keys
- Enabling storage backends
- Enabling terminal extras
- Changing ports
- Setting up automated updates

## Verification

Check your configuration syntax:

```bash
cd ~/user-config
nix flake check .
```

View what would be built (dry run):

```bash
sudo nixos-rebuild dry-run --flake .#HOSTNAME
```

## Reverting Changes

If something breaks:

```bash
# See available generations
sudo nixos-rebuild list-generations

# Rollback to previous generation
sudo nixos-rebuild switch --rollback
```

## Need More Options?

For complete option reference, see the full documentation files in nixoa-vm:
- `CONFIGURATION.md` - Complete options list
- `modules/xo/xoa.nix` - XO service options
- `modules/core/` - Core system modules
