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
      fixtureInputs = [
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.git
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
      ];
      mkSourceCheck = {
        name,
        command,
        nativeBuildInputs ? fixtureInputs,
      }:
        pkgs.runCommandLocal "nixoa-${name}" {inherit nativeBuildInputs;} ''
          cp -R ${inputs.self} source
          chmod -R u+w source
          cd source
          export HOME="$TMPDIR/home"
          export NIXOA_CI=${lib.getExe packages.nixoa-ci}
          export NIXOA_SYSTEM_ROOT="$PWD"
          mkdir -p "$HOME"
          ${command}
          touch "$out"
        '';
    in {
      inherit
        (packages)
        metadata
        nixoa-ci
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
            pkgs.bash
            pkgs.yq-go
            pkgs.zizmor
          ];
        } ''
          cp -R ${inputs.self} source
          cd source
          actionlint .github/workflows/*.yml
          zizmor .github/workflows
          while IFS= read -r action; do
            case "$action" in
              ./*) ;;
              *@????????????????????????????????????????) ;;
              *)
                printf 'Action is not pinned to a full commit: %s\n' "$action" >&2
                exit 1
                ;;
            esac
          done < <(
            yq -r '.. | .uses? | select(. != null)' .github/workflows/*.yml |
              grep -v '^---$'
          )
          if yq -r '.jobs[].steps[]?.run // ""' .github/workflows/*.yml | grep -F './ci/'; then
            printf 'Workflow directly invokes an unpackaged ci script.\n' >&2
            exit 1
          fi
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
            installer/*.sh \
            packer/*.sh \
            packer/scripts/*.sh \
            scripts/*.sh \
            scripts/lib/*.sh \
            scripts/tui/*.sh \
            nix/automation/*.sh \
            tests/*.sh
          touch "$out"
        '';

      automation-fixtures = mkSourceCheck {
        name = "automation-fixtures";
        command = "bash ./tests/ci-helpers.sh";
      };

      installer-input-fixtures = mkSourceCheck {
        name = "installer-input-fixtures";
        command = "bash ./tests/installer-build-input.sh";
      };

      release-fixtures = mkSourceCheck {
        name = "release-fixtures";
        command = "bash ./tests/release-assets.sh";
      };

      secretspec-contract =
        pkgs.runCommandLocal "nixoa-secretspec-contract" {
          nativeBuildInputs = [
            pkgs.jq
            packages.secretspec
          ];
        } ''
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          secretspec schema \
            --file ${inputs.self}/secretspec.toml \
            --profile github \
            --output github-schema.json
          jq -e '.required == ["CACHIX_CACHE_NAME"]' github-schema.json >/dev/null
          secretspec schema \
            --file ${inputs.self}/secretspec.toml \
            --profile github-publish \
            --output publish-schema.json
          jq -e \
            '.required == ["CACHIX_AUTH_TOKEN", "CACHIX_CACHE_NAME"]' \
            publish-schema.json >/dev/null
          touch "$out"
        '';

      operator-fixtures = mkSourceCheck {
        name = "operator-fixtures";
        command = "NIXOA_SKIP_EVAL=1 bash ./tests/run.sh";
      };

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
