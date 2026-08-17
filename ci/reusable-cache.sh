#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

operation=${1:?usage: reusable-cache.sh export|restore CACHE_DIR}
cache_dir=${2:?usage: reusable-cache.sh export|restore CACHE_DIR}
nix_bin=${NIX_BIN:-nix}
nix_store_dir=${NIX_STORE_DIR:-/nix/store}
workspace=${NIXOA_WORKSPACE:-$PWD}

case "$cache_dir" in
  /*) ;;
  *) cache_dir="$PWD/$cache_dir" ;;
esac

cache_uri="file://${cache_dir}"
manifest="$cache_dir/nixoa-roots.json"

validate_store_path() {
  store_name=${1#"$nix_store_dir/"}
  [[ "$1" == "$nix_store_dir/"* && "$store_name" =~ ^[0-9a-z]{32}-.+ ]] || {
    printf 'Invalid reusable cache store path: %s\n' "$1" >&2
    exit 1
  }
}

case "$operation" in
  export)
    [[ ! -e "$cache_dir" ]] || {
      printf 'Refusing to replace reusable cache directory: %s\n' "$cache_dir" >&2
      exit 1
    }
    install -d -m 0755 "$cache_dir"

    names=(deploy-template metadata nixoa-menu nxcli)
    roots=()
    for name in "${names[@]}"; do
      root=$(readlink -f "$workspace/result-$name")
      validate_store_path "$root"
      roots+=("$root")
    done

    "$nix_bin" copy --to "$cache_uri" "${roots[@]}"
    jq -n \
      --arg deploy_template "${roots[0]}" \
      --arg metadata "${roots[1]}" \
      --arg nixoa_menu "${roots[2]}" \
      --arg nxcli "${roots[3]}" \
      '{schema_version:1,roots:[{name:"deploy-template",store_path:$deploy_template},{name:"metadata",store_path:$metadata},{name:"nixoa-menu",store_path:$nixoa_menu},{name:"nxcli",store_path:$nxcli}]}' \
      >"$manifest"
    ;;
  restore)
    jq -e '
      .schema_version == 1 and
      (.roots | type == "array" and length == 4) and
      ([.roots[].name] | sort == ["deploy-template", "metadata", "nixoa-menu", "nxcli"]) and
      all(.roots[]; .store_path | type == "string")
    ' "$manifest" >/dev/null
    mapfile -t roots < <(jq -r '.roots[].store_path' "$manifest")
    for root in "${roots[@]}"; do
      validate_store_path "$root"
    done
    "$nix_bin" copy --no-check-sigs --from "$cache_uri" "${roots[@]}"
    for root in "${roots[@]}"; do
      "$nix_bin" path-info "$root" >/dev/null
    done
    ;;
  *)
    printf 'Unknown reusable cache operation: %s\n' "$operation" >&2
    exit 1
    ;;
esac
