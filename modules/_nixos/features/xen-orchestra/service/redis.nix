# SPDX-License-Identifier: Apache-2.0
# XO Redis/Valkey backend
{
  config,
  lib,
  pkgs,
  context,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.nixoa.xo;
in
{
  config = mkIf context.enableXO {
    services.redis.package = pkgs.valkey;
    services.redis.servers.xo = {
      enable = true;
      user = cfg.user;
      unixSocket = "/run/redis-xo/redis.sock";
      unixSocketPerm = 770;
      settings = {
        port = 0;
        databases = 16;
        maxmemory = "256mb";
        maxmemory-policy = "allkeys-lru";
      };
    };
  };
}
