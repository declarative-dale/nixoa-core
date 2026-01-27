# Daily Operations

Common commands for operating NiXOA systems (from the host).

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

## Configuration Changes

```bash
cd ~/user-config
./scripts/show-diff.sh
./scripts/apply-config.sh "Describe change"
```

Edit settings under `config/` in the system repo.

## Manual Rebuild

```bash
cd ~/user-config
sudo nixos-rebuild switch --flake .#HOSTNAME -L
```

## Rollback

```bash
sudo nixos-rebuild switch --rollback
```
