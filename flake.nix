{
  description = "NiXOA - Den-native Xen Orchestra appliance flake with unified host management";

  outputs = inputs: let
    outputAliases = import ./lib/output-aliases.nix {lib = inputs.nixpkgs.lib;};
    baseFlake =
      (
        inputs.nixpkgs.lib.evalModules {
          modules = [(inputs.import-tree ./modules)];
          specialArgs = {inherit inputs;};
        }
      ).config.flake;
    selectedVmOutput = outputAliases.selectedVmOutput ./.;
    baseNixosConfigurations = baseFlake.nixosConfigurations or {};
    vmAlias = outputAliases.vmAlias baseNixosConfigurations selectedVmOutput;
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
    xen-orchestra-ce.url = "git+https://github.com/declarative-dale/xo-nixpkg.git?ref=refs/tags/latest";
  };
}
