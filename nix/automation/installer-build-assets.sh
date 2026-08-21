#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
: "${NIXOA_SPDX_SCHEMA:?NIXOA_SPDX_SCHEMA must point to the pinned SPDX schema}"

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
manifest_xo_out=$(jq -er \
  '.results[] | select(.name == "xen-orchestra-ce") | .outputs | select(length == 1) | .[0]' \
  "$manifest")
[[ "$manifest_xo_out" == "$xo_out" ]]
xo_supply_out=$(jq -er \
  '.results[] | select(.name == "xen-orchestra-supply-protector") | .outputs | select(length == 1) | .[0]' \
  "$manifest")

(cd "$xo_supply_out" && sha256sum --check --strict SHA256SUMS)
nix-store --query --references "$xo_supply_out" | grep -Fx -- "$xo_out" >/dev/null
cache_url=https://xen-orchestra-ce.cachix.org
cache_key='xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E='
jq -e \
  --arg cache_key "$cache_key" \
  --arg cache_url "$cache_url" \
  --arg xo_out "$xo_out" '
  .schemaVersion == 1 and
  .subject.name == "xen-orchestra-ce" and
  .subject.channel == "latest" and
  .subject.storePath == $xo_out and
  .distribution.substituter == $cache_url and
  .distribution.trustedPublicKey == $cache_key
' "$xo_supply_out/assertion.json" >/dev/null

asserted_spdx_sha=$(jq -er .documents.spdx.sha256 "$xo_supply_out/assertion.json")
asserted_cdx_sha=$(jq -er .documents.cyclonedx.sha256 "$xo_supply_out/assertion.json")
[[ "$(sha256sum "$xo_supply_out/xen-orchestra.spdx.json" | cut -d' ' -f1)" == "$asserted_spdx_sha" ]]
[[ "$(sha256sum "$xo_supply_out/xen-orchestra.cdx.json" | cut -d' ' -f1)" == "$asserted_cdx_sha" ]]

install -m 0644 "$xo_supply_out/assertion.json" xen-orchestra-supply.assertion.json
install -m 0644 "$xo_supply_out/xen-orchestra.spdx.json" xen-orchestra-supply.spdx.json
install -m 0644 "$xo_supply_out/xen-orchestra.cdx.json" xen-orchestra-supply.cdx.json

sbom_work=$(mktemp -d "${runner_temp}/nixoa-sbom.XXXXXX")
trap 'rm -rf -- "$sbom_work"; rm -f -- "$manifest"' EXIT
(
  cd "$sbom_work"
  "$sbomnix_out/bin/sbomnix" \
    "path:${repo_root}#nixosConfigurations.nixoa.config.system.build.toplevel"
)
mv "$sbom_work/sbom.spdx.json" nixoa-system.spdx.json
mv "$sbom_work/sbom.cdx.json" nixoa-system.cdx.json

xo_version=$(jq -er .subject.version xen-orchestra-supply.assertion.json)
xo_document_namespace=$(jq -er .documentNamespace xen-orchestra-supply.spdx.json)
xo_document_root=$(jq -er '
  [.relationships[] |
    select(.spdxElementId == "SPDXRef-DOCUMENT" and .relationshipType == "DESCRIBES") |
    .relatedSpdxElement] |
  select(length == 1) | .[0]
' xen-orchestra-supply.spdx.json)
core_xo_element=$(jq -er --arg version "$xo_version" '
  [.packages[] |
    select(.name == "xen-orchestra-ce" and .versionInfo == $version) |
    .SPDXID] |
  select(length == 1) | .[0]
' nixoa-system.spdx.json)

jq -S \
  --arg core_xo_element "$core_xo_element" \
  --arg namespace "$xo_document_namespace" \
  --arg root "$xo_document_root" \
  --arg sha256 "$asserted_spdx_sha" '
  .externalDocumentRefs = ((.externalDocumentRefs // []) + [{
    externalDocumentId: "DocumentRef-XOSupply",
    spdxDocument: $namespace,
    checksum: {algorithm: "SHA256", checksumValue: $sha256}
  }]) |
  .relationships += [{
    spdxElementId: $core_xo_element,
    relationshipType: "DESCRIBED_BY",
    relatedSpdxElement: ("DocumentRef-XOSupply:" + $root)
  }]
' nixoa-system.spdx.json >"$sbom_work/nixoa-system.spdx.json"
mv "$sbom_work/nixoa-system.spdx.json" nixoa-system.spdx.json

jq -e --arg core_xo_element "$core_xo_element" --arg root "$xo_document_root" --arg sha256 "$asserted_spdx_sha" '
  any(.externalDocumentRefs[];
    .externalDocumentId == "DocumentRef-XOSupply" and
    .checksum.algorithm == "SHA256" and
    .checksum.checksumValue == $sha256) and
  any(.relationships[];
    .spdxElementId == $core_xo_element and
    .relationshipType == "DESCRIBED_BY" and
    .relatedSpdxElement == ("DocumentRef-XOSupply:" + $root))
' nixoa-system.spdx.json >/dev/null
check-jsonschema --schemafile "$NIXOA_SPDX_SCHEMA" nixoa-system.spdx.json
jq -e '.bomFormat == "CycloneDX"' nixoa-system.cdx.json >/dev/null

sha256sum result-installer/iso/nixoa-installer.iso >nixoa-installer.iso.sha256
sha256sum nixoa-system.spdx.json >nixoa-system.spdx.json.sha256
sha256sum nixoa-system.cdx.json >nixoa-system.cdx.json.sha256
sha256sum xen-orchestra-supply.assertion.json >xen-orchestra-supply.assertion.json.sha256
sha256sum xen-orchestra-supply.spdx.json >xen-orchestra-supply.spdx.json.sha256
sha256sum xen-orchestra-supply.cdx.json >xen-orchestra-supply.cdx.json.sha256
