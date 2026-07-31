{
  inputs,
  lib,
  ...
}: let
  systems = ["x86_64-linux"];
in {
  flake.checks = lib.genAttrs systems (
    system: let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      packages = inputs.self.packages.${system};
      appliance = inputs.self.nixosConfigurations.nixoa.config;
    in {
      inherit
        (packages)
        metadata
        nxcli
        ;

      eval-smoke = pkgs.runCommandLocal "nixoa-eval-smoke" {} ''
        mkdir -p "$out"
        printf '%s\n' "NiXOA appliance flake evaluation smoke check" > "$out/README"
      '';

      shell-tests =
        pkgs.runCommandLocal "nixoa-shell-tests" {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.git
            pkgs.gnugrep
            pkgs.gnused
            pkgs.shellcheck
          ];
        } ''
          cp -R ${inputs.self} source
          chmod -R u+w source
          cd source
          shellcheck scripts/*.sh scripts/lib/*.sh scripts/tui/*.sh tests/run.sh
          NIXOA_SKIP_EVAL=1 bash ./tests/run.sh
          touch "$out"
        '';

      configuration = assert appliance.nixoa.xo.enable;
      assert appliance.nixoa.xo.package == inputs.xen-orchestra-ce.packages.x86_64-linux.xen-orchestra-ce;
      assert appliance.services.redis.servers.xo.enable;
      assert appliance.systemd.services ? xo-autocert;
      assert appliance.nixoa.xo.internal.sudoWrapper != null;
      assert builtins.elem "multi-user.target" appliance.systemd.services.xen-guest-agent.wantedBy;
      assert appliance.services.openssh.settings.AllowUsers == ["nixoa"];
      assert appliance.networking.firewall.allowedTCPPorts == [22 80 443];
      assert appliance.determinate.enable;
      assert appliance.home-manager.users.nixoa.programs.git.enable;
      assert appliance.nix.gc.automatic;
      assert appliance.boot.loader.systemd-boot.configurationLimit == 10;
        pkgs.runCommandLocal "nixoa-configuration-assertions" {} ''
          touch "$out"
        '';
    }
  );
}
