# SPDX-License-Identifier: Apache-2.0
# XO Redis/Valkey backend
{
  lib,
  pkgs,
  vars,
  ...
}:
let
  inherit (lib) mkIf;
  xoUser = vars.xoUser;
in
{
  config = mkIf vars.enableXO {
    services.redis.package = pkgs.valkey;
    services.redis.servers.xo = {
      enable = true;
      user = xoUser;
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
