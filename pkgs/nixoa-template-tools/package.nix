{
  coreutils,
  gawk,
  gh,
  git,
  jq,
  lib,
  nix,
  packerXenserver,
  writeShellApplication,
}: let
  buildTemplate = writeShellApplication {
    name = "nixoa-build-template";
    runtimeInputs = [
      coreutils
      gawk
      gh
      git
      jq
      nix
      packerXenserver
    ];
    text = builtins.readFile ../../packer/build.sh;
    meta = {
      description = "Build a native NiXOA XCP-ng template with Packer";
      license = lib.licenses.asl20;
      mainProgram = "nixoa-build-template";
      platforms = ["x86_64-linux"];
    };
  };

  deployTemplate = writeShellApplication {
    name = "nixoa-deploy-template";
    runtimeInputs = [
      buildTemplate
      coreutils
      git
      jq
    ];
    text = builtins.readFile ../../packer/deploy-template.sh;
    meta = {
      description = "Configure and deploy a native NiXOA XCP-ng template";
      license = lib.licenses.asl20;
      mainProgram = "nixoa-deploy-template";
      platforms = ["x86_64-linux"];
    };
  };
in {
  build = buildTemplate;
  deploy = deployTemplate;
}
