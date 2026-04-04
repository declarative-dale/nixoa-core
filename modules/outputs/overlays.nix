{
  inputs,
  ...
}:
{
  flake.overlays = {
    nixoa = final: _prev:
      let
        system = final.stdenv.hostPlatform.system;
      in
      {
        nixoa =
          {
            xen-orchestra-ce = inputs.xen-orchestra-ce.packages.${system}.xen-orchestra-ce;
          }
          // inputs.nixpkgs.lib.optionalAttrs final.stdenv.hostPlatform.isLinux {
            nixoa-menu = final.callPackage ../../pkgs/nixoa-menu/package.nix { };
          };
      };

    default = inputs.self.overlays.nixoa;
  };
}
