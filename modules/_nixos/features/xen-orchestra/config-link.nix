# SPDX-License-Identifier: Apache-2.0
# XO Server configuration rendered from declarative TOML text
{
  config,
  lib,
  pkgs,
  context,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.nixoa.xo;
  tlsCfg = cfg.tls;
  contextConfig = context.xoConfig or {};
  contextToml =
    if builtins.isString contextConfig
    then contextConfig
    else if contextConfig ? toml
    then contextConfig.toml
    else "";

  defaultConfig = {
    redis.socket = "/run/redis-xo/redis.sock";
    dataStore.path = cfg.dataDir;
    tempDir.path = cfg.tempDir;
    http = {
      redirectToHttps = context.enableTLS;
      listen =
        [
          {
            port = 80;
          }
        ]
        ++ lib.optionals context.enableTLS [
          {
            port = 443;
            cert = tlsCfg.cert;
            key = tlsCfg.key;
          }
        ];
      mounts = {
        "/" = "${cfg.home}/xen-orchestra/@xen-orchestra/web/dist";
        "/v5" = "${cfg.home}/xen-orchestra/packages/xo-web/dist";
        "/v6" = "${cfg.home}/xen-orchestra/@xen-orchestra/web/dist";
      };
    };
    remoteOptions = {
      useSudo = true;
      mountsDir = context.mountsDir;
    };
  };

  configuredToml =
    if cfg.config.toml != ""
    then cfg.config.toml
    else contextToml;
  renderedToml = pkgs.writeText "config.nixoa.toml" configuredToml;
  renderedJson = pkgs.writeText "config.nixoa.json" (builtins.toJSON defaultConfig);
  renderedConfig =
    if configuredToml != ""
    then
      pkgs.runCommand "config.nixoa.toml" {} ''
        cp ${renderedToml} $out
        ${pkgs.remarshal}/bin/remarshal -if toml -of json "$out" >/dev/null
      ''
    else
      pkgs.runCommand "config.nixoa.toml" {} ''
        ${pkgs.remarshal}/bin/remarshal -if json -of toml ${renderedJson} > $out
        ${pkgs.remarshal}/bin/remarshal -if toml -of json "$out" >/dev/null
      '';
in {
  config = mkIf context.enableXO {
    nixoa.xo.config.toml = lib.mkIf (contextToml != "") contextToml;

    environment.etc."xo-server/config.nixoa.toml" = {
      source = renderedConfig;
      mode = "0644";
    };
  };
}
