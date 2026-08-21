#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
: "${NIXOA_SPDX_SCHEMA:?NIXOA_SPDX_SCHEMA must point to the pinned SPDX schema}"
: "${QUALIFICATION_MODE:?QUALIFICATION_MODE must be a supported qualification mode}"

repo_root=${NIXOA_SYSTEM_ROOT:-}
if [[ -z "$repo_root" ]]; then
  repo_root=$(git rev-parse --show-toplevel)
fi
cd "$repo_root"
runner_temp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
media_manifest=
manifest=
sbom_work=
cleanup() {
  [[ -z "$sbom_work" ]] || rm -rf -- "$sbom_work"
  [[ -z "$manifest" ]] || rm -f -- "$manifest"
  [[ -z "$media_manifest" ]] || rm -f -- "$media_manifest"
}
trap cleanup EXIT

case "$QUALIFICATION_MODE" in
  qualify-media|qualify-media-reuse-evidence)
    media_manifest=$(mktemp "${runner_temp}/nixoa-media-plan.XXXXXX")
    flake-plan-runner --flake "path:$repo_root" --plan lib.ciPlans.x86_64-linux.media --manifest "$media_manifest"
    ;;
  refresh-evidence)
    reused_installer=reused-media/result-installer
    [[ -f "$reused_installer/iso/nixoa-installer.iso" ]]
    mv "$reused_installer" result-installer
    ;;
  *)
    printf 'Unsupported qualification mode: %s\n' "$QUALIFICATION_MODE" >&2
    exit 1
    ;;
esac

nix config show substituters
nix config show trusted-public-keys
determinate_out=$(nix eval --accept-flake-config --raw .#nixosConfigurations.nixoa.config.nix.package.upstream.outPath)
nix path-info --store https://install.determinate.systems "$determinate_out"
xo_out=$(nix eval --accept-flake-config --raw .#packages.x86_64-linux.xen-orchestra-ce.outPath)
nix path-info --store https://xen-orchestra-ce.cachix.org "$xo_out"

manifest=$(mktemp "${runner_temp}/nixoa-plan.XXXXXX")
flake-plan-runner --flake "path:$repo_root" --plan lib.ciPlans.x86_64-linux.evidence --manifest "$manifest"

sbomnix_out=$(jq -er '.results[] | select(.name == "sbomnix") | .outputs | select(length == 1) | .[0]' "$manifest")
manifest_xo_out=$(jq -er '.results[] | select(.name == "xen-orchestra-ce") | .outputs | select(length == 1) | .[0]' "$manifest")
[[ "$manifest_xo_out" == "$xo_out" ]]
xo_supply_out=$(jq -er '.results[] | select(.name == "xen-orchestra-supply-protector") | .outputs | select(length == 1) | .[0]' "$manifest")

if [[ "$QUALIFICATION_MODE" == qualify-media-reuse-evidence ]]; then
  : "${EXPECTED_EVIDENCE_INPUT:?EXPECTED_EVIDENCE_INPUT must identify reused evidence}"
  : "${EXPECTED_EVIDENCE_RUN_ID:?EXPECTED_EVIDENCE_RUN_ID must identify reused evidence}"
  jq -e --arg evidence_input "$EXPECTED_EVIDENCE_INPUT" --argjson evidence_run_id "$EXPECTED_EVIDENCE_RUN_ID" '
      .schema_version == 4 and
      .evidence_input == $evidence_input and
      .evidence_run_id == $evidence_run_id
    ' reused-evidence/nixoa-qualification-state.json >/dev/null
  for evidence_file in nixoa-system.spdx.json nixoa-system.spdx.json.sha256 nixoa-system.cdx.json nixoa-system.cdx.json.sha256 xen-orchestra-supply.assertion.json xen-orchestra-supply.assertion.json.sha256 xen-orchestra-supply.spdx.json xen-orchestra-supply.spdx.json.sha256 xen-orchestra-supply.cdx.json xen-orchestra-supply.cdx.json.sha256; do
    install -m 0644 "reused-evidence/$evidence_file" "$evidence_file"
  done
else
  (cd "$xo_supply_out" && sha256sum --check --strict SHA256SUMS)
  install -m 0644 "$xo_supply_out/assertion.json" xen-orchestra-supply.assertion.json
  install -m 0644 "$xo_supply_out/xen-orchestra.spdx.json" xen-orchestra-supply.spdx.json
  install -m 0644 "$xo_supply_out/xen-orchestra.cdx.json" xen-orchestra-supply.cdx.json

  sbom_work=$(mktemp -d "${runner_temp}/nixoa-sbom.XXXXXX")
  (
    cd "$sbom_work"
    "$sbomnix_out/bin/sbomnix" "path:${repo_root}#nixosConfigurations.nixoa.config.system.build.toplevel"
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

  jq -S --arg core_xo_element "$core_xo_element" --arg namespace "$xo_document_namespace" --arg root "$xo_document_root" --arg sha256 "$(jq -er .documents.spdx.sha256 xen-orchestra-supply.assertion.json)" '
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

  sha256sum nixoa-system.spdx.json >nixoa-system.spdx.json.sha256
  sha256sum nixoa-system.cdx.json >nixoa-system.cdx.json.sha256
  sha256sum xen-orchestra-supply.assertion.json >xen-orchestra-supply.assertion.json.sha256
  sha256sum xen-orchestra-supply.spdx.json >xen-orchestra-supply.spdx.json.sha256
  sha256sum xen-orchestra-supply.cdx.json >xen-orchestra-supply.cdx.json.sha256
fi

(cd "$xo_supply_out" && sha256sum --check --strict SHA256SUMS)
nix-store --query --references "$xo_supply_out" | grep -Fx -- "$xo_out" >/dev/null
cache_url=https://xen-orchestra-ce.cachix.org
cache_key='xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E='
jq -e --arg cache_key "$cache_key" --arg cache_url "$cache_url" --arg xo_out "$xo_out" '
  .schemaVersion == 1 and
  .subject.name == "xen-orchestra-ce" and
  .subject.channel == "latest" and
  .subject.storePath == $xo_out and
  .distribution.substituter == $cache_url and
  .distribution.trustedPublicKey == $cache_key
' xen-orchestra-supply.assertion.json >/dev/null

asserted_spdx_sha=$(jq -er .documents.spdx.sha256 xen-orchestra-supply.assertion.json)
asserted_cdx_sha=$(jq -er .documents.cyclonedx.sha256 xen-orchestra-supply.assertion.json)
[[ "$(sha256sum xen-orchestra-supply.spdx.json | cut -d' ' -f1)" == "$asserted_spdx_sha" ]]
[[ "$(sha256sum xen-orchestra-supply.cdx.json | cut -d' ' -f1)" == "$asserted_cdx_sha" ]]

xo_version=$(jq -er .subject.version xen-orchestra-supply.assertion.json)
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

(
  sha256sum --check --strict nixoa-system.spdx.json.sha256
  sha256sum --check --strict nixoa-system.cdx.json.sha256
  sha256sum --check --strict xen-orchestra-supply.assertion.json.sha256
  sha256sum --check --strict xen-orchestra-supply.spdx.json.sha256
  sha256sum --check --strict xen-orchestra-supply.cdx.json.sha256
)
check-jsonschema --schemafile "$NIXOA_SPDX_SCHEMA" nixoa-system.spdx.json
jq -e '.bomFormat == "CycloneDX"' nixoa-system.cdx.json >/dev/null

installer_iso=result-installer/iso/nixoa-installer.iso
installer_budget_bytes=${NIXOA_INSTALLER_ARTIFACT_BUDGET_BYTES:-3000000000}
installer_size_bytes=$(stat -c %s "$installer_iso")
if (( installer_size_bytes > installer_budget_bytes )); then
  printf 'Installer ISO is %s bytes, exceeding the %s-byte artifact budget\n' \
    "$installer_size_bytes" "$installer_budget_bytes" >&2
  exit 1
fi
printf 'Installer ISO size: %s bytes (budget: %s bytes)\n' \
  "$installer_size_bytes" "$installer_budget_bytes"
sha256sum result-installer/iso/nixoa-installer.iso >nixoa-installer.iso.sha256
