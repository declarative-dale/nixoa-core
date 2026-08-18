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
  '';
  meta.description = "Refresh NiXOA's native devenv lock with pinned tooling";
}
