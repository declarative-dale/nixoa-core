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
  sudo,
}:

rustPlatform.buildRustPackage {
  pname = "nixoa-menu";
  version = "0.4.0";

  src = lib.cleanSource ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram "$out/bin/nixoa-menu" \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          gawk
          git
          gnugrep
          gnused
          inetutils
          iproute2
          nix
          sudo
        ]
      }
  '';

  meta = {
    description = "Ratatui-based SSH administration console for NiXOA system hosts";
    homepage = "https://codeberg.org/NiXOA/core";
    license = lib.licenses.asl20;
    mainProgram = "nixoa-menu";
    platforms = lib.platforms.linux;
  };
}
