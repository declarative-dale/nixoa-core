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
}:
rustPlatform.buildRustPackage {
  pname = "nixoa-menu";
  version = "0.6.0";

  src = lib.cleanSource ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [makeWrapper];

  postInstall = ''
    wrapProgram "$out/bin/nixoa-menu" \
      ${lib.optionalString (repoRootDefault != null) "--set-default NIXOA_SYSTEM_ROOT ${lib.escapeShellArg repoRootDefault} \\"}
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
