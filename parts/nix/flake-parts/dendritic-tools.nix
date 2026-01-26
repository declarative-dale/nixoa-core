{
  inputs,
  ...
}:
{
  # Core flake-parts wiring for the dendritic layout.
  flake-file.inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-file.url = "github:vic/flake-file";
    import-tree.url = "github:vic/import-tree";
  };

  imports = [
    inputs.flake-parts.flakeModules.modules
    inputs.flake-file.flakeModules.default
  ];

  # Import flake-parts modules from the dendritic tree.
  flake-file.outputs = ''
    inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./parts)
  '';

  systems = [
    "x86_64-linux"
  ];
}
