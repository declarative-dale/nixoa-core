# NiXOA: Xen Orchestra on NixOS

Run Xen Orchestra (an open-source hypervisor management platform) on NixOS with a declarative, version-controlled configuration.

## What is NiXOA?

NiXOA combines three powerful tools:
- **NixOS** - A reproducible Linux distribution
- **Xen Orchestra** - Open-source management for XCP-NG virtualization
- **Declarative configuration** - Define your entire system in code

The result is a system that's reproducible, auditable, and easy to version control.

## Quick Links

- **Getting Started**: [Installation & First Deployment](./docs/getting-started.md)
- **Installation**: [Detailed Installation Guide](./docs/installation.md)
- **Configuration**: [How to Configure NiXOA](./docs/configuration.md)
- **Daily Operations**: [Managing Your System](./docs/operations.md)
- **Common Tasks**: [Configuration Examples](./docs/common-tasks.md)
- **Troubleshooting**: [Problem Solving Guide](./docs/troubleshooting.md)
- **Architecture**: [How NiXOA is Structured](./docs/architecture.md)

## Features

- ✅ Automated Xen Orchestra installation and management
- ✅ HTTPS with auto-generated certificates
- ✅ NFS and CIFS remote storage support
- ✅ Redis caching (Unix socket)
- ✅ SSH-only admin access (no password login)
- ✅ Automated system updates with rollback capability
- ✅ Real-time network monitoring (Snitch)
- ✅ Systemd-boot or GRUB boot loader options

## First Time Here?

**Start with:** [Getting Started Guide](./docs/getting-started.md)

It walks you through installation and first deployment in about 5 minutes.

## Already Installed?

**Check:** [Daily Operations](./docs/operations.md) for how to manage your system

## Need Specific Help?

- **Configuration examples**: [Common Tasks](./docs/common-tasks.md)
- **Something broken?**: [Troubleshooting](./docs/troubleshooting.md)
- **Understand the architecture**: [Architecture Guide](./docs/architecture.md)

## Important Notes

This is **not production-ready** software. It's designed for homelab and testing environments. For production use, purchase the official [Xen Orchestra Appliance](https://xen-orchestra.com/) from Vates.

## Resources

- **Xen Orchestra docs**: [https://xen-orchestra.com/docs/](https://xen-orchestra.com/docs/)
- **NixOS learn**: [https://nixos.org/learn.html](https://nixos.org/learn.html)
- **Get help**: [https://codeberg.org/nixoa/nixoa-vm/issues](https://codeberg.org/nixoa/nixoa-vm/issues)

## License

Apache 2.0
