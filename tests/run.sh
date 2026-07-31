#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_ROOT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "expected '$2', got '$1'"
}

temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

bash -n \
  "$TEST_ROOT/scripts/lib/common.sh" \
  "$TEST_ROOT/scripts/nxcli.sh" \
  "$TEST_ROOT/scripts/bootstrap.sh" \
  "$TEST_ROOT/scripts/tui/lib.sh" \
  "$TEST_ROOT/scripts/tui/action.sh" \
  "$TEST_ROOT/scripts/tui/state.sh"

# Fixed target resolution.
actual="$(
  NIXOA_SYSTEM_ROOT="$TEST_ROOT" bash -c '
    source "$NIXOA_SYSTEM_ROOT/scripts/lib/common.sh"
    nixoa_default_target
    nixoa_host_output_name
    nixoa_nixos_rebuild_flake_ref
  '
)"
expected="$(
  printf 'nixoa\nnixoa\npath:%s#nixoa' "$TEST_ROOT"
)"
assert_eq "$actual" "$expected"

if NIXOA_SYSTEM_ROOT="$TEST_ROOT" bash -c '
  source "$NIXOA_SYSTEM_ROOT/scripts/lib/common.sh"
  nixoa_resolve_target_output vm
' >/dev/null 2>&1
then
  fail "legacy vm target still resolves"
fi

# Removed multi-host CLI commands fail explicitly.
for command in add list select-vm; do
  if NIXOA_SYSTEM_ROOT="$TEST_ROOT" bash "$TEST_ROOT/scripts/nxcli.sh" host "$command" \
    >"$temporary/$command.out" 2>"$temporary/$command.err"
  then
    fail "nxcli host $command unexpectedly succeeded"
  fi
  grep -q 'was removed' "$temporary/$command.err" \
    || fail "nxcli host $command did not explain its removal"
done

if NIXOA_SYSTEM_ROOT="$TEST_ROOT" bash "$TEST_ROOT/scripts/nxcli.sh" apply --target vm \
  >"$temporary/target.out" 2>"$temporary/target.err"
then
  fail "apply accepted a target selector"
fi
grep -q 'Target selection was removed' "$temporary/target.err" \
  || fail "apply did not reject target selection clearly"

if bash "$TEST_ROOT/scripts/bootstrap.sh" --hostname legacy \
  >"$temporary/bootstrap.out" 2>"$temporary/bootstrap.err"
then
  fail "bootstrap accepted legacy hostname selection"
fi
grep -q 'was removed' "$temporary/bootstrap.err" \
  || fail "bootstrap did not reject legacy identity options"

# Bootstrap settings generation populates the fixed identity and supplied keys.
mkdir -p "$temporary/generated/host"
NIXOA_SYSTEM_ROOT="$temporary/generated" bash -c '
  source "'"$TEST_ROOT"'/scripts/lib/common.sh"
  keys=("ssh-ed25519 AAAATEST operator@example")
  nixoa_write_host_settings \
    "$NIXOA_SETTINGS_FILE" \
    "/home/nixoa/nixoa" \
    "America/Chicago" \
    "26.05" \
    "Test Operator" \
    "operator@example.com" \
    keys
'
grep -q 'networking.hostName = "nixoa";' "$temporary/generated/host/settings.nix" \
  || fail "generated settings do not fix the nixoa hostname"
grep -q 'ssh-ed25519 AAAATEST operator@example' "$temporary/generated/host/settings.nix" \
  || fail "generated settings omitted the SSH key"
grep -q 'nixoa.xo = {' "$temporary/generated/host/settings.nix" \
  || fail "generated settings omitted XO"

# TUI writes only the dedicated native-option override module.
cp "$TEST_ROOT/host/settings.nix" "$temporary/generated/host/settings.nix"
cp "$TEST_ROOT/host/menu.nix" "$temporary/generated/host/menu.nix"
NIXOA_SYSTEM_ROOT="$temporary/generated" bash -c '
  source "'"$TEST_ROOT"'/scripts/tui/lib.sh"
  keys=("ssh-ed25519 AAAATEST operator@example")
  system_packages=("ripgrep")
  user_packages=("jq")
  services=("tailscale")
  nixoa_tui_write_menu \
    true \
    true \
    keys \
    system_packages \
    user_packages \
    services
'
grep -q 'nixoa.operator = {' "$temporary/generated/host/menu.nix" \
  || fail "TUI override does not use typed operator options"
grep -q 'extraSystemPackages = \[' "$temporary/generated/host/menu.nix" \
  || fail "TUI override omitted system packages"
grep -q 'enabledServices = \[' "$temporary/generated/host/menu.nix" \
  || fail "TUI override omitted service enables"
if grep -qE 'networking\.hostName|time\.timeZone' "$temporary/generated/host/menu.nix"; then
  fail "TUI override owns durable host identity settings"
fi
if grep -q '_ctx\\|deploymentProfile\\|enableXenHardware' "$temporary/generated/host/menu.nix"; then
  fail "TUI override contains legacy host context"
fi

# Verify the exact generated override composes in a complete flake evaluation.
if [ "${NIXOA_SKIP_EVAL:-0}" != 1 ]; then
  cp -a "$TEST_ROOT" "$temporary/repo"
  cp "$temporary/generated/host/menu.nix" "$temporary/repo/host/menu.nix"
  env XDG_CACHE_HOME="$temporary/cache" nix eval --raw \
    "path:$temporary/repo#nixosConfigurations.nixoa.config.system.build.toplevel.drvPath" \
    >/dev/null
fi

printf 'All NiXOA shell tests passed.\n'
