# SPDX-License-Identifier: Apache-2.0
# XO Redis/Valkey backend
{
  config,
  lib,
  pkgs,
  context,
  ...
}: let
  inherit (lib) mkIf mkOption optionalAttrs types;
  cfg = config.nixoa.xo;
in {
  options.nixoa.xo.redis = {
    maxmemory = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "256mb";
      description = ''
        Optional Redis/Valkey maxmemory limit for the XO database.

        Leave null to use Redis' normal unlimited 64-bit default. If this is
        set, keep the eviction policy at noeviction unless this Redis instance
        is intentionally being used as a cache.
      '';
    };

    maxmemoryPolicy = mkOption {
      type = types.str;
      default = "noeviction";
      description = "Redis/Valkey maxmemory policy for the XO database.";
    };
  };

  config = mkIf context.enableXO {
    services.redis.package = pkgs.valkey;
    services.redis.servers.xo = {
      enable = true;
      user = cfg.user;
      unixSocket = "/run/redis-xo/redis.sock";
      unixSocketPerm = 770;
      settings =
        {
          port = 0;
          databases = 16;
          maxmemory-policy = cfg.redis.maxmemoryPolicy;
        }
        // optionalAttrs (cfg.redis.maxmemory != null) {
          maxmemory = cfg.redis.maxmemory;
        };
    };
  };
}
