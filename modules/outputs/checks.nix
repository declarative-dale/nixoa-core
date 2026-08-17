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

      workflow-policy =
        pkgs.runCommandLocal "nixoa-workflow-policy" {
          nativeBuildInputs = [
            pkgs.actionlint
            pkgs.zizmor
          ];
        } ''
          cp -R ${inputs.self} source
          cd source
          actionlint .github/workflows/*.yml
          zizmor .github/workflows
          touch "$out"
        '';

      shell-lint =
        pkgs.runCommandLocal "nixoa-shell-lint" {
          nativeBuildInputs = [
            pkgs.shellcheck
          ];
        } ''
          cd ${inputs.self}
          shellcheck \
            ci/*.sh \
            installer/*.sh \
            packer/*.sh \
            packer/scripts/*.sh \
            scripts/*.sh \
            scripts/lib/*.sh \
            scripts/tui/*.sh \
            tests/*.sh
          touch "$out"
        '';

      fixture-tests =
        pkgs.runCommandLocal "nixoa-fixture-tests" {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.git
            pkgs.gnugrep
            pkgs.gnused
            pkgs.jq
          ];
        } ''
          cp -R ${inputs.self} source
          chmod -R u+w source
          cd source
          NIXOA_SKIP_EVAL=1 bash ./tests/run.sh
          touch "$out"
        '';

      repository-policy = import ../../nix/checks/repository-policy.nix {
        inherit lib pkgs;
        source = inputs.self;
      };

      configuration = assert appliance.nixoa.xo.enable;
      assert appliance.nixoa.xo.package == inputs.xen-orchestra-ce.packages.x86_64-linux.xen-orchestra-ce;
      assert appliance.services.redis.servers.xo.enable;
      assert appliance.systemd.services ? xo-autocert;
      assert appliance.nixoa.xo.internal.sudoWrapper != null;
      assert builtins.elem "multi-user.target" appliance.systemd.services.xen-guest-agent.wantedBy;
      assert appliance.services.cloud-init.enable;
      assert !appliance.services.cloud-init.network.enable;
      assert appliance.services.cloud-init.settings.datasource_list == ["NoCloud" "None"];
      assert appliance.services.cloud-init.settings.system_info.default_user.name == "nixoa";
      assert appliance.services.cloud-init.settings.cloud_init_modules
      == [
        "seed_random"
        "growpart"
        "resizefs"
      ];
      assert appliance.services.cloud-init.settings.growpart.devices == ["/"];
      assert appliance.services.cloud-init.settings.resize_rootfs;
      assert appliance.services.cloud-init.settings.network.config == "disabled";
      assert appliance.services.cloud-init.settings.disable_network_activation;
      assert appliance.services.cloud-init.settings.ssh_genkeytypes == [];
      assert !appliance.services.cloud-init.settings.ssh.emit_keys_to_console;
      assert appliance.security.polkit.enable;
      assert builtins.elem pkgs.cloud-init appliance.environment.systemPackages;
      assert builtins.elem "cloud-config.service" appliance.systemd.services.sshd.after;
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
