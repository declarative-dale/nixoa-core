# SPDX-License-Identifier: Apache-2.0
# XO Server configuration rendered from declarative TOML text
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
  tlsCfg = cfg.tls;
  contextConfig = context.xoConfig or { };

  defaultToml = ''
    [redis]
    socket = "/run/redis-xo/redis.sock"

    [dataStore]
    path = "${cfg.dataDir}"

    [tempDir]
    path = "${cfg.tempDir}"

    [http]
    redirectToHttps = true

    [[http.listen]]
    port = 80

    [[http.listen]]
    port = 443
    cert = "${tlsCfg.cert}"
    key = "${tlsCfg.key}"

    [http.mounts]
    "/" = "${cfg.home}/xen-orchestra/@xen-orchestra/web/dist"
    "/v5" = "${cfg.home}/xen-orchestra/packages/xo-web/dist"
    "/v6" = "${cfg.home}/xen-orchestra/@xen-orchestra/web/dist"

    [remoteOptions]
    useSudo = true
    mountsDir = "${context.mountsDir}"
  '';

  contextToml =
    if builtins.isString contextConfig then
      contextConfig
    else if contextConfig ? toml then
      contextConfig.toml
    else
      defaultToml;
  renderedToml = pkgs.writeText "xo-config.nixoa.toml" cfg.config.toml;
  renderedConfig = pkgs.runCommand "config.nixoa.toml" { } ''
    cp ${renderedToml} $out
    ${pkgs.remarshal}/bin/remarshal -if toml -of json "$out" >/dev/null
  '';
in
{
  config = mkIf context.enableXO {
    nixoa.xo.config.toml = contextToml;

    environment.etc."xo-server/config.nixoa.toml" = {
      source = renderedConfig;
      mode = "0644";
    };
  };
}
