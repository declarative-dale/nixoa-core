{
  inputs,
  nixoa,
  ...
}:
let
  overlay = final: _prev:
    let
      system = final.stdenv.hostPlatform.system;
    in
    {
      nixoa =
        {
          xen-orchestra-ce = inputs.xen-orchestra-ce.packages.${system}.xen-orchestra-ce;
          libvhdi = inputs.xen-orchestra-ce.packages.${system}.libvhdi;
        }
        // inputs.nixpkgs.lib.optionalAttrs final.stdenv.hostPlatform.isLinux {
          nixoa-menu = final.callPackage ../../pkgs/nixoa-menu/package.nix { };
        };
    };
in
{
  nixoa.xen-orchestra.nixos = {
    _module.args.nixoaInputs = inputs;
    nixpkgs.overlays = [ overlay ];

    imports = [
      ../nixos/features/shared/context.nix
      ../nixos/features/xen-orchestra/options-base.nix
      ../nixos/features/xen-orchestra/options-paths.nix
      ../nixos/features/xen-orchestra/options-tls.nix
      ../nixos/features/xen-orchestra/config-link.nix
      ../nixos/features/xen-orchestra/service/account.nix
      ../nixos/features/xen-orchestra/service/assertions.nix
      ../nixos/features/xen-orchestra/service/limits.nix
      ../nixos/features/xen-orchestra/service/redis.nix
      ../nixos/features/xen-orchestra/service/packages.nix
      ../nixos/features/xen-orchestra/service/start-script.nix
      ../nixos/features/xen-orchestra/service/unit.nix
      ../nixos/features/xen-orchestra/service/tmpfiles.nix
      ../nixos/features/xen-orchestra/storage/libvhdi-options.nix
      ../nixos/features/xen-orchestra/storage/wrapper-script.nix
      ../nixos/features/xen-orchestra/storage/sudo-config.nix
      ../nixos/features/xen-orchestra/storage/packages.nix
      ../nixos/features/xen-orchestra/storage/filesystems.nix
      ../nixos/features/xen-orchestra/storage/sudo-rules.nix
      ../nixos/features/xen-orchestra/storage/sudo-init.nix
      ../nixos/features/xen-orchestra/storage/tmpfiles.nix
      ../nixos/features/xen-orchestra/storage/assertions.nix
      ../nixos/features/xen-orchestra/tls-service.nix
      ../nixos/features/xen-orchestra/tls-tmpfiles.nix
      ../nixos/features/xen-orchestra/cli.nix
    ];
  };
}
