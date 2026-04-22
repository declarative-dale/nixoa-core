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
  jq,
  makeWrapper,
  nix,
  nixos-rebuild,
  nh,
  sudo,
  systemd,
  symlinkJoin,
  util-linux,
  writeShellScriptBin,
  repoRootDefault ? null,
}:

let
  version = "4.0.0";

  nxcliScript = writeShellScriptBin "nxcli" ''
    ${lib.optionalString (repoRootDefault != null) ''
      if [ -z "''${NIXOA_SYSTEM_ROOT:-}" ]; then
        export NIXOA_SYSTEM_ROOT=${lib.escapeShellArg repoRootDefault}
      fi
    ''}

    ${builtins.readFile ../../scripts/nxcli.sh}
  '';
in
symlinkJoin {
  name = "nxcli-${version}";
  paths = [ nxcliScript ];
  nativeBuildInputs = [ makeWrapper ];

  postBuild = ''
    wrapProgram "$out/bin/nxcli" \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          findutils
          gawk
          git
          glibc.bin
          gnugrep
          gnused
          inetutils
          jq
          nix
          nixos-rebuild
          nh
          sudo
          systemd
          util-linux
        ]
      }
  '';

  meta = {
    description = "Canonical NiXOA operator CLI";
    homepage = "https://codeberg.org/NiXOA/core";
    license = lib.licenses.asl20;
    mainProgram = "nxcli";
    platforms = lib.platforms.linux;
  };
}
