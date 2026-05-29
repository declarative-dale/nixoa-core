{
  lib,
  bash,
  coreutils,
  gawk,
  git,
  gnugrep,
  gnused,
  inetutils,
  iproute2,
  makeWrapper,
  nix,
  rustPlatform,
  repoRootDefault ? null,
}: let
  runtimePath = lib.makeBinPath [
    bash
    coreutils
    gawk
    git
    gnugrep
    gnused
    inetutils
    iproute2
    nix
  ];
  wrapperArgs =
    lib.optionals (repoRootDefault != null) [
      "--set-default"
      "NIXOA_SYSTEM_ROOT"
      repoRootDefault
    ]
    ++ [
      "--prefix"
      "PATH"
      ":"
      runtimePath
    ];
in
  rustPlatform.buildRustPackage {
    pname = "nixoa-menu";
    version = "0.6.0";

    src = lib.cleanSource ./.;

    cargoLock = {
      lockFile = ./Cargo.lock;
    };

    nativeBuildInputs = [makeWrapper];

    postInstall = ''
      wrapProgram "$out/bin/nixoa-menu" ${lib.escapeShellArgs wrapperArgs}
    '';

    meta = {
      description = "Ratatui-based SSH administration console for NiXOA system hosts";
      homepage = "https://codeberg.org/NiXOA/core";
      license = lib.licenses.asl20;
      mainProgram = "nixoa-menu";
      platforms = lib.platforms.linux;
    };
  }
