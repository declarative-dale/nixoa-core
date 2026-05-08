{
  lib,
  bash,
  coreutils,
  findutils,
  gawk,
  git,
  glibc,
  gnugrep,
  gnused,
  inetutils,
  iproute2,
  jq,
  nix,
  nixos-rebuild,
  nh,
  systemd,
  util-linux,
  writeShellApplication,
  repoRootDefault ? null,
}:
writeShellApplication {
  name = "nxcli";
  runtimeInputs = [
    bash
    coreutils
    findutils
    gawk
    git
    glibc.bin
    gnugrep
    gnused
    inetutils
    iproute2
    jq
    nix
    nixos-rebuild
    nh
    systemd
    util-linux
  ];
  checkPhase = ":";
  text = ''
    ${lib.optionalString (repoRootDefault != null) ''
      if [ -z "''${NIXOA_SYSTEM_ROOT:-}" ]; then
        export NIXOA_SYSTEM_ROOT=${lib.escapeShellArg repoRootDefault}
      fi
    ''}

    ${builtins.readFile ../../scripts/nxcli.sh}
  '';

  meta = {
    description = "Canonical NiXOA operator CLI";
    homepage = "https://codeberg.org/NiXOA/core";
    license = lib.licenses.asl20;
    mainProgram = "nxcli";
    platforms = lib.platforms.linux;
  };
}
