# Daily Operations

Common commands for operating NiXOA systems from the unified repo.

## Service Management

```bash
sudo systemctl status xo-server.service
sudo systemctl restart xo-server.service
sudo systemctl status redis-xo.service
```

## Logs

```bash
sudo journalctl -u xo-server -f
sudo journalctl -u xo-server -n 200
```

## Review Configuration Changes

```bash
cd ~/nixoa
./scripts/show-diff.sh
```

Edit the active host under `host/<hostname>/`, usually `_ctx/settings.nix`
and `_ctx/menu.nix`.

## Apply Configuration

Preferred `nh` flow:

```bash
cd ~/nixoa
nh os switch .#nixosConfigurations.<hostname>
```

Wrapper script:

```bash
cd ~/nixoa
./scripts/apply-config.sh --hostname <hostname>
```

Stable VM target:

```bash
cd ~/nixoa
nh os build .#nixosConfigurations.vm
./scripts/apply-config.sh --hostname vm --build
```

## Build Without Switching

```bash
cd ~/nixoa
nh os build .#nixosConfigurations.<hostname>
```

## Rollback

```bash
cd ~/nixoa
./scripts/apply-config.sh --hostname <hostname> --rollback
```
