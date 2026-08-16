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

bash "$TEST_ROOT/tests/installer-build-input.sh"

bash -n \
  "$TEST_ROOT/ci/installer-build-input.sh" \
  "$TEST_ROOT/scripts/lib/common.sh" \
  "$TEST_ROOT/scripts/nxcli.sh" \
  "$TEST_ROOT/scripts/bootstrap.sh" \
  "$TEST_ROOT/scripts/tui/lib.sh" \
  "$TEST_ROOT/scripts/tui/action.sh" \
  "$TEST_ROOT/scripts/tui/state.sh" \
  "$TEST_ROOT/installer/install-nixoa.sh" \
  "$TEST_ROOT/packer/build.sh" \
  "$TEST_ROOT/packer/deploy-template.sh" \
  "$TEST_ROOT/tests/installer-build-input.sh" \
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
grep -Fq '.#packages.x86_64-linux.xen-orchestra-ce' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not build Xen Orchestra explicitly"
# The variable reference must remain literal in the workflow source.
# shellcheck disable=SC2016
grep -Fq 'nix path-info --store https://xen-orchestra-ce.cachix.org "${xo_out}"' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not verify that its Xen Orchestra output is cached"
grep -Fq 'DeterminateSystems/determinate-nix-action@61cbfe2efc2d4e7a8a6d56967c3c1058e846c858' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not pin Determinate Nix to an immutable revision"
grep -Fq 'DeterminateSystems/magic-nix-cache-action@908b263ff629f4cc17666315b7fd3ec127c6244d' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not use the GitHub-backed Magic Nix Cache"
grep -Fq 'use-gha-cache: enabled' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not explicitly use the free GitHub cache"
grep -Fq 'use-flakehub: disabled' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow unexpectedly probes the paid FlakeHub cache"
grep -Fq 'cachix/cachix-action@5f2d7c5294214f71b873db4b969586b980625e71' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow no longer retains Cachix publishing support"
grep -Fq 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not pin the Node.js 24 artifact uploader"
# The command substitution must remain literal in the workflow source.
# shellcheck disable=SC2016
grep -Fq 'build_input=$(./ci/installer-build-input.sh)' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not calculate deterministic build state"
grep -Fq "if: needs.plan.outputs.should_build == 'true'" \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer build is not gated by the state planner"
grep -Fq 'name: nixoa-build-state' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not publish its immutable state pointer"
# The variable reference must remain literal in the workflow source.
# shellcheck disable=SC2016
grep -Fq '"${sbomnix_out}/bin/sbomnix"' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not generate SBOMs with sbomnix"
grep -Fq 'nixoa-system.spdx.json' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not publish an SPDX SBOM"
grep -Fq 'nixoa-system.cdx.json' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not publish a CycloneDX SBOM"
grep -Fq 'DeterminateSystems/flakehub-push@abcff4fb351e63f852f5fb2b9af0ae4e69de07d4' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "rolling FlakeHub publication does not use the current Node.js 24 action"
grep -Fq 'rolling-minor: 2' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "rolling FlakeHub publication does not avoid the legacy version line"
grep -Fq -- '--status completed' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer state cannot recover verified artifacts from late failures"
grep -Fq -- '- "!docs/**"' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not exclude documentation changes"
grep -Fq -- '- "!**/*.md"' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not exclude Markdown changes"
grep -Fq -- '- "!**/README*"' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not exclude README changes"
grep -Fq -- '- "!**/CHANGELOG*"' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml" \
  || fail "installer workflow does not exclude changelog changes"
[[ ! -e "$TEST_ROOT/.github/workflows/flakehub-publish-tagged.yml" ]] \
  || fail "obsolete standalone FlakeHub runner still exists"
if grep -q 'result-installer)' \
  "$TEST_ROOT/.github/workflows/cache-nixoa-menu.yml"; then
  fail "installer workflow still pushes the full ISO closure to Cachix"
fi
grep -Fq 'cron: "17 9 * * 3"' \
  "$TEST_ROOT/.github/workflows/update-flake-lock.yml" \
  || fail "flake input refresh is not scheduled weekly on Wednesday"
grep -Fq 'DeterminateSystems/update-flake-lock@834c491b2ece4de0bbd00d85214bb5e83b4da5c6' \
  "$TEST_ROOT/.github/workflows/update-flake-lock.yml" \
  || fail "flake input refresh does not pin the lock update action"
grep -Fq 'DeterminateSystems/flake-checker-action@de924abd783455e8429c858962b9e43062d19da1' \
  "$TEST_ROOT/.github/workflows/validate.yml" \
  || fail "validation does not pin the flake checker action"
grep -Fq 'fail-mode: true' \
  "$TEST_ROOT/.github/workflows/validate.yml" \
  || fail "validation does not enforce flake input findings"
if grep -Fq 'inputs:' \
  "$TEST_ROOT/.github/workflows/update-flake-lock.yml"; then
  fail "flake input refresh unexpectedly limits the inputs it updates"
fi
grep -Fq '2.0.1-dev.0' "$TEST_ROOT/VERSION" \
  || fail "development version does not follow the published v2.0.0 release"
grep -Fq -- '--draft' "$TEST_ROOT/.github/workflows/release.yml" \
  || fail "release workflow does not stage assets in a draft"
grep -Fq 'candidate-state/nixoa-build-state.json' \
  "$TEST_ROOT/.github/workflows/release.yml" \
  || fail "release workflow does not resolve the immutable build state"
grep -Fq 'actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c' \
  "$TEST_ROOT/.github/workflows/release.yml" \
  || fail "release workflow does not use the latest immutable artifact downloader"
# The variable reference must remain literal in the workflow source.
# shellcheck disable=SC2016
grep -Fq 'gh release edit "${RELEASE_TAG}" --draft=false --latest' \
  "$TEST_ROOT/.github/workflows/release.yml" \
  || fail "release workflow does not publish the verified immutable draft"
# The variable reference must remain literal in the workflow source.
# shellcheck disable=SC2016
grep -Fq 'Start NiXOA ${next_version}' \
  "$TEST_ROOT/.github/workflows/release.yml" \
  || fail "release workflow does not advance the development version"
grep -Fq 'package-ecosystem: github-actions' \
  "$TEST_ROOT/.github/dependabot.yml" \
  || fail "GitHub Actions updates are not managed by Dependabot"
grep -Fq 'automation/weekly-flake-input-refresh' \
  "$TEST_ROOT/.github/workflows/queue-automation.yml" \
  || fail "trusted flake updates are not eligible for the automation queue"
grep -Fq '"growpart"' "$TEST_ROOT/modules/_nixos/xcp-ng.nix" \
  || fail "installed appliance does not enable cloud-init growpart"
grep -Fq '"resizefs"' "$TEST_ROOT/modules/_nixos/xcp-ng.nix" \
  || fail "installed appliance does not resize the grown root filesystem"

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
  --disk-size-mb 20480 \
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
  and .disk_size_mb == 20480
  and (.remote_password? == null)
' "$temporary/packer.pkrvars.json" >/dev/null \
  || fail "Packer configuration generation is incorrect"

# The default Packer build downloads the newest successful, checksum-verified
# GitHub artifact and does not duplicate the large ISO into the checkout.
mkdir -p \
  "$temporary/fake-result/iso" \
  "$temporary/fake-artifact/result-installer/iso" \
  "$temporary/fake-state" \
  "$temporary/bin"
printf 'fake installer image\n' >"$temporary/fake-result/iso/nixoa-installer.iso"
cp \
  "$temporary/fake-result/iso/nixoa-installer.iso" \
  "$temporary/fake-artifact/result-installer/iso/nixoa-installer.iso"
(
  cd "$temporary/fake-artifact"
  sha256sum \
    result-installer/iso/nixoa-installer.iso \
    >nixoa-installer.iso.sha256
)
printf '%s\n' \
  '{"schema_version":1,"build_input":"fixture-state","source_commit":"fixture-source","artifact_source_commit":"fixture-source","artifact_run_id":12345}' \
  >"$temporary/fake-state/nixoa-build-state.json"
cp "$temporary/fake-state/nixoa-build-state.json" \
  "$temporary/fake-artifact/nixoa-build-state.json"
# The variable references belong in the generated fake, not this test shell.
# shellcheck disable=SC2016
printf '%s\n' \
  "#!$(command -v bash)" \
  'printf "%s\n" "$*" >>"$FAKE_GH_ARGS"' \
  'if [[ "$1 $2" == "run list" ]]; then printf "12345\n"; exit 0; fi' \
  'if [[ "$1 $2" == "run download" ]]; then' \
  '  artifact_name=' \
  '  artifact_dir=' \
  '  while [[ "$#" -gt 0 ]]; do' \
  '    case "$1" in' \
  '      --name) artifact_name=$2; shift 2 ;;' \
  '      --dir) artifact_dir=$2; shift 2 ;;' \
  '      *) shift ;;' \
  '    esac' \
  '  done' \
  '  if [[ "$artifact_name" == "nixoa-build-state" ]]; then' \
  '    cp -R "$FAKE_STATE_DIR/." "$artifact_dir/"' \
  '  else' \
  '    cp -R "$FAKE_ARTIFACT_DIR/." "$artifact_dir/"' \
  '  fi' \
  '  exit 0' \
  'fi' \
  'exit 1' \
  >"$temporary/bin/gh"
# The variable reference belongs in the generated fake, not this test shell.
# shellcheck disable=SC2016
printf '%s\n' \
  "#!$(command -v bash)" \
  'printf "%s\n" "$@" >"$FAKE_NIX_ARGS"' \
  'printf "%s\n" "$FAKE_INSTALLER_RESULT"' \
  >"$temporary/bin/nix"
# The variable references belong in the generated fake, not this test shell.
# shellcheck disable=SC2016
printf '%s\n' \
  "#!$(command -v bash)" \
  'printf "%s\n" "$@" >"$FAKE_PACKER_ARGS"' \
  >"$temporary/bin/packer"
chmod +x "$temporary/bin/gh" "$temporary/bin/nix" "$temporary/bin/packer"
FAKE_ARTIFACT_DIR="$temporary/fake-artifact" \
  FAKE_STATE_DIR="$temporary/fake-state" \
  FAKE_GH_ARGS="$temporary/gh.args" \
  FAKE_PACKER_ARGS="$temporary/packer.args" \
  GH_BIN="$temporary/bin/gh" \
  PACKER_BIN="$temporary/bin/packer" \
  OPERATOR_PUBLIC_KEY_FILE="$temporary/operator.pub" \
  TMPDIR="$temporary" \
  bash "$TEST_ROOT/packer/build.sh"
grep -Eq '^iso_url=.*/nixoa-installer\.iso$' \
  "$temporary/packer.args" \
  || fail "Packer build did not use the downloaded GitHub artifact"
grep -Fq -- '--workflow cache-nixoa-menu.yml' "$temporary/gh.args" \
  || fail "artifact lookup did not select the installer workflow"
grep -Fq -- '--name nixoa-installer' "$temporary/gh.args" \
  || fail "artifact download did not select the installer artifact"
[[ ! -e "$temporary/output/nixoa-installer.iso" ]] \
  || fail "Packer build duplicated the installer ISO into the checkout"

# A local Nix build remains an explicit fallback and also passes its store
# artifact directly to Packer.
FAKE_INSTALLER_RESULT="$temporary/fake-result" \
  FAKE_NIX_ARGS="$temporary/nix.args" \
  FAKE_PACKER_ARGS="$temporary/packer.args" \
  NIX_BIN="$temporary/bin/nix" \
  PACKER_BIN="$temporary/bin/packer" \
  OPERATOR_PUBLIC_KEY_FILE="$temporary/operator.pub" \
  INSTALLER_SOURCE=build \
  bash "$TEST_ROOT/packer/build.sh"
grep -Fxq \
  "iso_url=$temporary/fake-result/iso/nixoa-installer.iso" \
  "$temporary/packer.args" \
  || fail "Packer build did not use the installer directly from the Nix store"
grep -Fxq -- '--accept-flake-config' "$temporary/nix.args" \
  || fail "installer substitution does not accept the flake cache configuration"
grep -Fxq 'output/' "$TEST_ROOT/.gitignore" \
  || fail "installer artifact directory is not ignored"
grep -Fxq '/http_cache.sqlite' "$TEST_ROOT/.gitignore" \
  || fail "sbomnix HTTP cache is not ignored"
grep -Fxq '/sbom.spdx.json' "$TEST_ROOT/.gitignore" \
  || fail "local sbomnix SPDX output is not ignored"

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
grep -q 'nixos-rebuild --accept-flake-config switch' \
  "$TEST_ROOT/packer/scripts/seal-template.sh" \
  || fail "Packer sealing does not accept the flake cache configuration"
grep -q 'nixoa_write_apply_state success switch' \
  "$TEST_ROOT/packer/scripts/seal-template.sh" \
  || fail "Packer sealing does not record its successful system switch"
grep -qx 'nh clean all' \
  "$TEST_ROOT/packer/scripts/seal-template.sh" \
  || fail "Packer sealing does not remove obsolete Nix generations"
grep -q 'last_apply_head=.*git -C /home/nixoa/nixoa rev-parse HEAD' \
  "$TEST_ROOT/packer/scripts/verify-clone.sh" \
  || fail "clone verification does not validate the sealed apply state"
grep -Fq 'd /var/lib/nixoa 0755 root root' \
  "$TEST_ROOT/modules/_nixos/operator.nix" \
  || fail "the shared NiXOA status directory is not operator-readable"
grep -Fq 'd /var/lib/nfs/sm.bak 0755 root root' \
  "$TEST_ROOT/modules/_nixos/xo/storage.nix" \
  || fail "NFS notification state is not created before first boot"
grep -q 'org\.freedesktop\.hostname1\.set-hostname' \
  "$TEST_ROOT/modules/_nixos/platform.nix" \
  || fail "platform does not authorize DHCP hostname adoption"
grep -q 'passwd --lock nixoa' \
  "$TEST_ROOT/packer/scripts/seal-template.sh" \
  || fail "Packer sealing does not lock the temporary operator password"
grep -q 'Timed out waiting for the Xen Orchestra HTTPS endpoint' \
  "$TEST_ROOT/packer/scripts/verify-template.sh" \
  || fail "Packer verification does not wait for XO HTTPS readiness"
test "$(grep -c 'XO_READINESS_GRACE_SECONDS=240' \
  "$TEST_ROOT/packer/builds.pkr.hcl")" -eq 1 \
  || fail "Packer must apply the four-minute XO grace period exactly once"
grep -q 'XO_READINESS_GRACE_SECONDS:-0' \
  "$TEST_ROOT/packer/scripts/verify-template.sh" \
  || fail "template verification does not default to immediate XO retries"

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
