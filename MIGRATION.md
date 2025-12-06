<!-- SPDX-License-Identifier: Apache-2.0 -->
# Migration Guide: Renaming Local Repository

If you have an existing installation with the old repository name, follow these steps to rename your local directory to match the new `nixoa-ce` naming convention.

## For System-Wide Installation (/etc/nixos)

If you cloned the repository to `/etc/nixos/nixoa` or `/etc/nixos/declarative-xoa-ce`:

```bash
# Stop XO services
sudo systemctl stop xo-server.service

# Navigate to parent directory
cd /etc/nixos

# Rename the directory
sudo mv nixoa nixoa-ce
# or if you had: sudo mv declarative-xoa-ce nixoa-ce

# Update your nixoa.toml file
cd nixoa-ce
sudo nano nixoa.toml
```

**In nixoa.toml, update the repoDir setting:**
```toml
[updates]
repoDir = "/etc/nixos/nixoa-ce"  # Update this line
```

**Update the git remote URL:**
```bash
# Check current remote
git remote -v

# Update to new repository URL
git remote set-url origin https://codeberg.org/dalemorgan/nixoa-ce.git

# Verify the change
git remote -v
```

**Rebuild the system:**
```bash
sudo nixos-rebuild switch --flake .#xoa -L
```

The services will automatically start after the rebuild.

---

## For User Home Directory Installation

If you cloned the repository to `~/nixoa` or `~/declarative-xoa-ce`:

```bash
# Stop XO services
sudo systemctl stop xo-server.service

# Navigate to home directory
cd ~

# Rename the directory
mv nixoa nixoa-ce
# or if you had: mv declarative-xoa-ce nixoa-ce

# Update your nixoa.toml file
cd nixoa-ce
nano nixoa.toml
```

**In nixoa.toml, update the repoDir setting:**
```toml
[updates]
repoDir = "~/nixoa-ce"  # Update this line
# Or use absolute path: repoDir = "/home/yourusername/nixoa-ce"
```

**Update the git remote URL:**
```bash
# Check current remote
git remote -v

# Update to new repository URL
git remote set-url origin https://codeberg.org/dalemorgan/nixoa-ce.git

# Verify the change
git remote -v
```

**Rebuild the system:**
```bash
sudo nixos-rebuild switch --flake .#xoa -L
```

---

## Verification

After migration, verify everything is working:

```bash
# Check services are running
sudo systemctl status xo-server.service
sudo systemctl status redis-xo.service

# Check web interface
curl -k https://localhost/

# Verify update timers (if enabled)
systemctl list-timers | grep xoa

# Check update status
sudo xoa-update-status
```

---

## Troubleshooting

**Issue:** Build fails with "directory not found" error

**Solution:** Verify the path in your nixoa.toml matches your actual directory:
```bash
# Check current directory
pwd

# Update nixoa.toml to match
nano nixoa.toml
```

**Issue:** Services won't start

**Solution:** Check service logs:
```bash
sudo journalctl -u xo-server.service -n 50
sudo journalctl -u xo-build.service -n 50
```

**Issue:** Automatic updates fail

**Solution:** Ensure repoDir in nixoa.toml is correct and the directory has git initialized with the correct remote:
```bash
cd /etc/nixos/nixoa-ce  # or your actual path
git status

# Check remote URL
git remote -v

# Should show: origin  https://codeberg.org/dalemorgan/nixoa-ce.git
# If not, update it:
git remote set-url origin https://codeberg.org/dalemorgan/nixoa-ce.git
```

---

## No Migration Needed

If you're doing a **fresh installation**, simply clone the repository with the new name:

```bash
# System-wide (recommended)
sudo mkdir -p /etc/nixos
cd /etc/nixos
sudo git clone https://codeberg.org/dalemorgan/nixoa-ce.git
cd nixoa-ce

# Or user home directory
cd ~
git clone https://codeberg.org/dalemorgan/nixoa-ce.git
cd nixoa-ce
```

The default `repoDir` in the sample configuration already points to `/etc/nixos/nixoa-ce`.
