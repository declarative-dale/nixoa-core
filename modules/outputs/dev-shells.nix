{
  inputs,
  lib,
  ...
}: let
  systems = ["x86_64-linux"];
in {
  flake.devShells = lib.genAttrs systems (system: let
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfreePredicate = package:
        lib.getName package == "packer";
    };
  in {
    # Keep `nix develop` as a lightweight compatibility entry point. Native
    # devenv owns the task graph and evaluation cache; both shells consume the
    # same package definition without compiling devenv's task engine here.
    default = pkgs.mkShellNoCC {
      packages = import ../../nix/devenv-packages.nix {inherit pkgs;};
    };
  });
}
