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
      xoPackages = inputs.xen-orchestra-ce.packages.${system};
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
        flake-plan-runner
        metadata
        nixoa-ci
        nxcli
        ;

      ci-plan-contract = let
        plans = inputs.self.lib.ciPlans.${system};
      in
        pkgs.runCommandLocal "nixoa-ci-plan-contract" {
          nativeBuildInputs = [pkgs.jq];
        } ''
          printf '%s\n' ${lib.escapeShellArg (builtins.toJSON plans)} > plans.json
          jq -e '
            (.validation.schemaVersion == 2) and
            (.validation.name == "nixoa-validation") and
            (.validation.targets | length == 16) and
            (.installer.schemaVersion == 2) and
            (.installer.name == "nixoa-installer") and
            (.installer.targets | length == 9) and
            (.publish.schemaVersion == 2) and
            (.publish.name == "nixoa-publish") and
            (.publish.targets | length == 5)
          ' plans.json >/dev/null
          touch "$out"
        '';

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
          zizmor .github
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
            yq -r '.. | .uses? | select(. != null)' \
              .github/workflows/*.yml \
              .github/actions/*/action.yml |
              grep -v '^---$'
          )
          if yq -r '.jobs[].steps[]?.run // ""' .github/workflows/*.yml |
            grep -v '^---$' |
            grep -Ev '^$|^nix run --accept-flake-config \.#devenv -- tasks run ci:check$|^nix run --accept-flake-config \.#devenv -- tasks run --mode single [a-z0-9:_-]+$'; then
            printf 'Workflow command bypasses the declared devenv task graph.\n' >&2
            exit 1
          fi
          touch "$out"
        '';

      devenv-contract =
        pkgs.runCommandLocal "nixoa-devenv-contract" {
          nativeBuildInputs = [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.jq
          ];
        } ''
          cd ${inputs.self}
          for task in \
            ci:prepare ci:classify ci:check ci:installer:plan ci:installer:build \
            ci:installer:boot ci:publish ci:gate automation:queue \
            automation:update-locks automation:validate-locks automation:open-lock-update-pr \
            release:prepare release:dispatch release:inventory release:verify \
            release:stage release:draft release:publish release:advance; do
            grep -Fq "\"$task\"" nix/devenv.nix
          done
          grep -Fq 'validate-plan PLAN.json' nix/automation/cli.sh
          grep -Fq 'pkgs.check-jsonschema' nix/automation/default.nix
          test "$(grep -c 'execIfModified = ' nix/devenv.nix)" -eq 2
          ! grep -Fq 'exec = "true";' nix/devenv.nix
          grep -Fq "git ls-files -z -- '*.nix'" nix/devenv.nix
          grep -Fq -- "-path './.devenv'" nix/devenv.nix
          grep -Fq 'DeterminateSystems/determinate-nix-action@61cbfe2efc2d4e7a8a6d56967c3c1058e846c858' \
            .github/actions/setup-nix/action.yml
          if grep -RqE '\.#nixoa-ci([ -]|$)|\.#nixoa-ci-installer-boot|\.#nixoa-ci-update-locks' .github/workflows; then
            printf 'A hosted workflow bypasses the declared devenv task graph.\n' >&2
            exit 1
          fi
          ${lib.getExe packages.nixoa-ci} locks validate \
            ${inputs.self}/flake.lock ${inputs.self}/devenv.lock
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
            modules/_nixos/xo/*.sh \
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
        nativeBuildInputs = fixtureInputs ++ [pkgs.yq-go];
      };

      repository-policy = import ../../nix/checks/repository-policy.nix {
        inherit lib pkgs;
        source = inputs.self;
      };

      configuration = assert appliance.nixoa.xo.enable;
      assert appliance.nixoa.xo.channel == "latest";
      assert lib.all (channel: builtins.hasAttr channel xoPackages) ["latest" "stable" "rolling"];
      assert appliance.nixoa.xo.package == xoPackages.latest;
      assert appliance.nixoa.xo.config.file != null;
      assert appliance.environment.etc."xo-server/config.nixoa.toml".source == appliance.nixoa.xo.config.file;
      assert (builtins.fromTOML (builtins.readFile appliance.nixoa.xo.config.file)).remoteOptions.mountsDir == appliance.nixoa.xo.storage.mountsDir;
      assert appliance.nixoa.xo.storage.libvhdiPackage == inputs.xen-orchestra-ce.packages.x86_64-linux.libvhdi;
      assert appliance.programs.fuse.userAllowOther;
      assert builtins.elem "fuse" appliance.users.users.${appliance.nixoa.xo.user}.extraGroups;
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
