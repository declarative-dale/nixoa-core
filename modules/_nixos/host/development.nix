# SPDX-License-Identifier: Apache-2.0
# Optional development tooling for hosts that explicitly enable Development Mode.
{
  lib,
  pkgs,
  context,
  ...
}: {
  config = lib.mkIf (context.developmentMode or false) {
    environment.systemPackages = with pkgs; [
      devenv

      cargo
      clippy
      rust-analyzer
      rustc
      rustfmt
      rustup

      openssl
      pkg-config

      corepack
      nodejs
      pnpm
      yarn

      redis
      valkey
    ];
  };
}
