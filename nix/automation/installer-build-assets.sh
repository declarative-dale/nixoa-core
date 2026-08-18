#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

repo_root=${NIXOA_SYSTEM_ROOT:-}
if [[ -z "$repo_root" ]]; then
  repo_root=$(git rev-parse --show-toplevel)
fi
cd "$repo_root"
runner_temp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}

nix config show substituters
nix config show trusted-public-keys
determinate_out=$(nix eval --raw .#nixosConfigurations.nixoa.config.nix.package.upstream.outPath)
nix path-info --store https://install.determinate.systems "$determinate_out"
xo_out=$(nix eval --raw .#packages.x86_64-linux.xen-orchestra-ce.outPath)
nix path-info --store https://xen-orchestra-ce.cachix.org "$xo_out"

nix flake show --accept-flake-config --all-systems
nix flake check --accept-flake-config --all-systems --no-build --print-build-logs
nix build \
  .#nixosConfigurations.nixoa.config.system.build.toplevel \
  .#packages.x86_64-linux.deploy-template \
  .#packages.x86_64-linux.libvhdi \
  .#packages.x86_64-linux.metadata \
  .#packages.x86_64-linux.nixoa-menu \
  .#packages.x86_64-linux.nxcli \
  .#packages.x86_64-linux.sbomnix \
  .#packages.x86_64-linux.xen-orchestra-ce \
  --no-link \
  --print-build-logs

nix build .#deploy-template -o result-deploy-template
nix build .#metadata -o result-metadata
nix build .#nixoa-menu -o result-nixoa-menu
nix build .#nxcli -o result-nxcli
nix build .#installer-iso -o result-installer --print-build-logs

sbomnix_out=$(nix build .#sbomnix --no-link --print-out-paths)
sbom_work=$(mktemp -d "${runner_temp}/nixoa-sbom.XXXXXX")
trap 'rm -rf -- "$sbom_work"' EXIT
(
  cd "$sbom_work"
  "$sbomnix_out/bin/sbomnix" \
    "path:${repo_root}#nixosConfigurations.nixoa.config.system.build.toplevel"
)
mv "$sbom_work/sbom.spdx.json" nixoa-system.spdx.json
mv "$sbom_work/sbom.cdx.json" nixoa-system.cdx.json
jq -e '.spdxVersion | startswith("SPDX-")' nixoa-system.spdx.json >/dev/null
jq -e '.bomFormat == "CycloneDX"' nixoa-system.cdx.json >/dev/null

sha256sum result-installer/iso/nixoa-installer.iso >nixoa-installer.iso.sha256
sha256sum nixoa-system.spdx.json >nixoa-system.spdx.json.sha256
sha256sum nixoa-system.cdx.json >nixoa-system.cdx.json.sha256
