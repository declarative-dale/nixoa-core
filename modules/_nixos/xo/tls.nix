# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixoa.xo;
  enabled = cfg.enable && cfg.tls.enable && cfg.tls.autoCert;
  generateCertificate = pkgs.writeShellApplication {
    name = "xo-generate-certificate";
    runtimeInputs = [pkgs.coreutils pkgs.openssl];
    text = ''
      export NIXOA_XO_TLS_CERT=${lib.escapeShellArg cfg.tls.cert}
      export NIXOA_XO_TLS_KEY=${lib.escapeShellArg cfg.tls.key}
      export NIXOA_XO_TLS_DIR=${lib.escapeShellArg cfg.tls.dir}
      export NIXOA_XO_HOSTNAME=${lib.escapeShellArg config.networking.hostName}
      export NIXOA_XO_HTTP_HOST=${lib.escapeShellArg cfg.httpHost}
      export NIXOA_XO_USER=${lib.escapeShellArg cfg.user}
      export NIXOA_XO_GROUP=${lib.escapeShellArg cfg.group}
      ${builtins.readFile ./autocert.sh}
    '';
  };
in {
  config = lib.mkIf enabled {
    systemd.tmpfiles.rules = [
      "d ${cfg.tls.dir} 0755 root root - -"
    ];
    systemd.services.xo-autocert = {
      description = "Generate the XO TLS certificate";
      wantedBy = ["multi-user.target"];
      after = [
        "local-fs.target"
        "systemd-tmpfiles-setup.service"
      ];
      before = ["xo-server.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe generateCertificate;
        User = "root";
        Group = "root";
      };
    };
  };
}
