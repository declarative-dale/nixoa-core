{
  description = "NiXOA - Den-native Xen Orchestra appliance flake with unified host management";

  outputs =
    inputs:
    let
      baseFlake =
        (
          inputs.nixpkgs.lib.evalModules {
            modules = [ (inputs.import-tree ./modules) ];
            specialArgs = { inherit inputs; };
          }
        ).config.flake;
      automation = import ./host/_automation/default.nix { };
      selectedVmHost = automation.vmHost or null;
      selectedVmOutput = if selectedVmHost == null then null else "${selectedVmHost}-vm";
      baseNixosConfigurations = baseFlake.nixosConfigurations or { };
      vmAlias =
        if selectedVmOutput != null && builtins.hasAttr selectedVmOutput baseNixosConfigurations then
          { vm = baseNixosConfigurations.${selectedVmOutput}; }
        else
          { };
    in
    baseFlake
    // {
      nixosConfigurations = baseNixosConfigurations // vmAlias;
    };

  inputs = {
    den.url = "github:denful/den/v0.16.0";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "https://flakehub.com/f/nix-community/home-manager/0";
    };
    import-tree.url = "github:vic/import-tree";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    snitch = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:karol-broda/snitch";
    };
    xen-orchestra-ce.url = "git+https://github.com/declarative-dale/xo-nixpkg.git?ref=refs/tags/latest";
  };
}
