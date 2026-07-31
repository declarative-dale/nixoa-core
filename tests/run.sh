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
  "$TEST_ROOT/scripts/tui/state.sh" \
  "$TEST_ROOT/installer/install-nixoa.sh" \
  "$TEST_ROOT/packer/build.sh" \
  "$TEST_ROOT/packer/deploy-template.sh" \
  "$TEST_ROOT"/packer/scripts/*.sh

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

# First-install builds use Determinate Systems' unauthenticated bootstrap cache
# rather than the authenticated FlakeHub Cache endpoint.
actual="$(
  NIXOA_SYSTEM_ROOT="$TEST_ROOT" bash -c '
    source "$NIXOA_SYSTEM_ROOT/scripts/lib/common.sh"
    command=()
    nixoa_append_first_install_nix_options command
    printf "%s\n" "${command[@]}"
  '
)"
grep -Fxq 'https://install.determinate.systems https://nixoa.cachix.org https://xen-orchestra-ce.cachix.org https://libvhdi-nixpkg.cachix.org' \
  <<<"$actual" \
  || fail "first-install command omits a required binary cache"
grep -Fxq 'cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM= nixoa.cachix.org-1:N+GsSSd2yKgj2hx01fMG6Oe7tLfbxEi/V0oZFEB721g= xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E= libvhdi-nixpkg.cachix.org-1:HvYHKZcfczn2nGfCmd7F21E/MDZrlaXtN3p9mWAZT/4=' \
  <<<"$actual" \
  || fail "first-install command omits a required cache signing key"
if grep -Fxq 'https://cache.flakehub.com' <<<"$actual"; then
  fail "first-install command uses the authenticated FlakeHub Cache endpoint"
fi
grep -Fq '"https://install.determinate.systems"' \
  "$TEST_ROOT/installer/default.nix" \
  || fail "installer ISO omits the Determinate bootstrap cache"
grep -Fq '"https://nixoa.cachix.org"' \
  "$TEST_ROOT/installer/default.nix" \
  || fail "installer ISO omits the NiXOA Cachix cache"
grep -Fq '"cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="' \
  "$TEST_ROOT/installer/default.nix" \
  || fail "installer ISO omits the Determinate bootstrap cache key"
grep -Fq '"nixoa.cachix.org-1:N+GsSSd2yKgj2hx01fMG6Oe7tLfbxEi/V0oZFEB721g="' \
  "$TEST_ROOT/installer/default.nix" \
  || fail "installer ISO omits the NiXOA Cachix key"
if grep -Fq '"https://cache.flakehub.com"' "$TEST_ROOT/installer/default.nix"; then
  fail "installer ISO uses the authenticated FlakeHub Cache endpoint"
fi
grep -Fq 'applianceToplevel' "$TEST_ROOT/installer/default.nix" \
  || fail "installer ISO omits the NiXOA appliance closure"
grep -Fq 'nixoaMenu' "$TEST_ROOT/installer/default.nix" \
  || fail "installer ISO omits nixoa-menu"
grep -Fq 'xenOrchestraCe' "$TEST_ROOT/installer/default.nix" \
  || fail "installer ISO omits Xen Orchestra"
grep -Fq 'result-xen-orchestra-ce' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "cache workflow does not publish Xen Orchestra explicitly"

# Installed systems keep all public appliance/build caches and avoid requesting
# Determinate's uncached manual output.
grep -Fq '"https://install.determinate.systems"' \
  "$TEST_ROOT/modules/_nixos/platform.nix" \
  || fail "installed system omits the Determinate bootstrap cache"
grep -Fq '"https://nixoa.cachix.org"' \
  "$TEST_ROOT/modules/_nixos/platform.nix" \
  || fail "installed system omits the NiXOA Cachix cache"
grep -Fq 'paths = [upstreamDeterminateNix.out]' \
  "$TEST_ROOT/modules/_nixos/platform.nix" \
  || fail "installed system does not isolate the cached Determinate runtime output"

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

# Packer configuration generation is fixed to one native NiXOA template and
# never persists the XCP-ng password.
printf '%s\n' 'ssh-ed25519 AAAATEST operator@example' \
  >"$temporary/operator.pub"
bash "$TEST_ROOT/packer/deploy-template.sh" \
  --host 192.0.2.10 \
  --username root \
  --iso-sr "ISO library" \
  --sr "Local storage" \
  --network "Build network" \
  --export-network "Template network" \
  --template-name NiXOA \
  --memory-mb 4096 \
  --disk-size-mb 51200 \
  --operator-key "$temporary/operator.pub" \
  --config "$temporary/packer.pkrvars.json" \
  --configure-only
jq -e '
  .remote_host == "192.0.2.10"
  and .remote_username == "root"
  and .sr_iso_name == "ISO library"
  and .sr_name == "Local storage"
  and .network_names == ["Build network"]
  and .export_network_names == ["Template network"]
  and .vm_name == "NiXOA"
  and .memory_mb == 4096
  and .disk_size_mb == 51200
  and (.remote_password? == null)
' "$temporary/packer.pkrvars.json" >/dev/null \
  || fail "Packer configuration generation is incorrect"

# The Packer build materializes a real, ignored installer artifact rather than
# leaving the user to chase a Nix store result symlink.
mkdir -p "$temporary/fake-result/iso" "$temporary/bin"
printf 'fake installer image\n' >"$temporary/fake-result/iso/nixoa-installer.iso"
# The variable reference belongs in the generated fake, not this test shell.
# shellcheck disable=SC2016
printf '%s\n' \
  "#!$(command -v bash)" \
  'printf "%s\n" "$FAKE_INSTALLER_RESULT"' \
  >"$temporary/bin/nix"
printf '%s\n' \
  "#!$(command -v bash)" \
  'exit 0' \
  >"$temporary/bin/packer"
chmod +x "$temporary/bin/nix" "$temporary/bin/packer"
FAKE_INSTALLER_RESULT="$temporary/fake-result" \
  NIX_BIN="$temporary/bin/nix" \
  PACKER_BIN="$temporary/bin/packer" \
  OPERATOR_PUBLIC_KEY_FILE="$temporary/operator.pub" \
  OUTPUT_DIR="$temporary/output" \
  bash "$TEST_ROOT/packer/build.sh"
cmp \
  "$temporary/fake-result/iso/nixoa-installer.iso" \
  "$temporary/output/nixoa-installer.iso" \
  || fail "Packer build did not materialize the installer artifact"
grep -Fxq 'output/' "$TEST_ROOT/.gitignore" \
  || fail "installer artifact directory is not ignored"

grep -q './packer.nix' "$TEST_ROOT/host/default.nix" \
  || fail "host does not import the dedicated Packer override"
if grep -qE 'PasswordAuthentication|hashedPassword' "$TEST_ROOT/host/packer.nix"; then
  fail "tracked Packer override contains temporary access policy"
fi
grep -q 'refusing to erase a disk without --yes' \
  "$TEST_ROOT/installer/install-nixoa.sh" \
  || fail "installer does not require explicit destructive confirmation"
grep -q 'mount -t ext4.*root_partition' \
  "$TEST_ROOT/installer/install-nixoa.sh" \
  || fail "installer does not explicitly mount its ext4 root"
grep -q 'mount -o fmask=0077,dmask=0077.*efi_partition' \
  "$TEST_ROOT/installer/install-nixoa.sh" \
  || fail "installer does not protect files on the EFI system partition"
grep -q 'cloud-init clean --logs --machine-id --seed' \
  "$TEST_ROOT/packer/scripts/seal-template.sh" \
  || fail "Packer sealing does not clear clone identity"
grep -q 'org\.freedesktop\.hostname1\.set-hostname' \
  "$TEST_ROOT/modules/_nixos/platform.nix" \
  || fail "platform does not authorize DHCP hostname adoption"
grep -q 'passwd --lock nixoa' \
  "$TEST_ROOT/packer/scripts/seal-template.sh" \
  || fail "Packer sealing does not lock the temporary operator password"
grep -q 'Timed out waiting for the Xen Orchestra HTTPS endpoint' \
  "$TEST_ROOT/packer/scripts/verify-template.sh" \
  || fail "Packer verification does not wait for XO HTTPS readiness"
grep -q 'XO_READINESS_GRACE_SECONDS=240' \
  "$TEST_ROOT/packer/scripts/verify-template.sh" \
  || fail "Packer verification does not give XO a four-minute startup grace period"

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

cat >"$temporary/xo-tls.toml" <<'EOF'
[[http.listen]]
port = 80

[[http.listen]]
cert = "/etc/ssl/xo/certificate.pem"
key = "/etc/ssl/xo/key.pem"
port = 443
EOF
NIXOA_SYSTEM_ROOT="$temporary/generated" bash -c '
  source "'"$TEST_ROOT"'/scripts/tui/lib.sh"
  nixoa_tui_xo_tls_enabled "'"$temporary"'/xo-tls.toml"
' || fail "TUI does not detect TLS from the rendered XO configuration"

cat >"$temporary/xo-http.toml" <<'EOF'
[[http.listen]]
port = 80
EOF
if NIXOA_SYSTEM_ROOT="$temporary/generated" bash -c '
  source "'"$TEST_ROOT"'/scripts/tui/lib.sh"
  nixoa_tui_xo_tls_enabled "'"$temporary"'/xo-http.toml"
'; then
  fail "TUI reports TLS without a certificate and key listener"
fi

cat >"$temporary/default-options.nix" <<'EOF'
{lib, ...}: {
  nixoa.operator = {
    sshKeys = lib.mkDefault [
      "ssh-ed25519 AAAATEST operator@example"
    ];
    enableExtras = lib.mkDefault true;
    extraSystemPackages = [];
  };
}
EOF
actual="$(
  NIXOA_SYSTEM_ROOT="$temporary/generated" bash -c '
    source "'"$TEST_ROOT"'/scripts/tui/lib.sh"
    nixoa_tui_read_bool_file enableExtras "'"$temporary"'/default-options.nix"
    nixoa_tui_read_list_file sshKeys "'"$temporary"'/default-options.nix"
    nixoa_tui_read_list_file extraSystemPackages "'"$temporary"'/default-options.nix"
  '
)"
assert_eq "$actual" $'true\nssh-ed25519 AAAATEST operator@example'
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
