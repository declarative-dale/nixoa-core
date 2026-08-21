{
  coreutils,
  findutils,
  git,
  gnugrep,
  gnused,
  lib,
  nix,
  writeShellApplication,
}:
writeShellApplication {
  name = "nixoa-bootstrap";
  runtimeInputs = [
    coreutils
    findutils
    git
    gnugrep
    gnused
    nix
  ];
  text = builtins.readFile ../../scripts/bootstrap.sh;
  meta = {
    description = "Bootstrap the fixed NiXOA appliance checkout";
    license = lib.licenses.asl20;
    mainProgram = "nixoa-bootstrap";
    platforms = ["x86_64-linux"];
  };
}
