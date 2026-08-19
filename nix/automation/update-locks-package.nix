{
  devenvSource,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "nixoa-ci-update-locks";
  runtimeInputs = [
    pkgs.git
    pkgs.nix
  ];
  text = ''
    cd "''${NIXOA_SYSTEM_ROOT:-$(git rev-parse --show-toplevel)}"
    nix run --accept-flake-config ${devenvSource}#devenv -- update
    nix flake update --accept-flake-config
  '';
  meta.description = "Refresh every NiXOA native and flake input with pinned tooling";
}
