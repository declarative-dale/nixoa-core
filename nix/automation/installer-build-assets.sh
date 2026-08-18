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
determinate_out=$(nix eval --accept-flake-config --raw .#nixosConfigurations.nixoa.config.nix.package.upstream.outPath)
nix path-info --store https://install.determinate.systems "$determinate_out"
xo_out=$(nix eval --accept-flake-config --raw .#packages.x86_64-linux.xen-orchestra-ce.outPath)
nix path-info --store https://xen-orchestra-ce.cachix.org "$xo_out"

manifest=$(mktemp "${runner_temp}/nixoa-plan.XXXXXX")
flake-plan-runner \
  --flake "path:$repo_root" \
  --plan lib.ciPlans.x86_64-linux.installer \
  --manifest "$manifest"

sbomnix_out=$(jq -er \
  '.results[] | select(.name == "sbomnix") | .outputs | select(length == 1) | .[0]' \
  "$manifest")
sbom_work=$(mktemp -d "${runner_temp}/nixoa-sbom.XXXXXX")
trap 'rm -rf -- "$sbom_work"; rm -f -- "$manifest"' EXIT
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
