# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixoa.xo;
  enabled = cfg.enable && cfg.tls.enable && cfg.tls.autoCert;
  generateCertificate = pkgs.writeShellScript "xo-generate-certificate" ''
    set -euo pipefail
    umask 077

    cert=${lib.escapeShellArg cfg.tls.cert}
    key=${lib.escapeShellArg cfg.tls.key}
    host=${lib.escapeShellArg config.networking.hostName}

    mkdir -p ${lib.escapeShellArg cfg.tls.dir}
    chmod 0755 ${lib.escapeShellArg cfg.tls.dir}

    if [ -s "$key" ] \
      && [ -s "$cert" ] \
      && ${pkgs.openssl}/bin/openssl x509 -checkend 0 -noout -in "$cert" 2>/dev/null
    then
      exit 0
    fi

    ${pkgs.openssl}/bin/openssl req \
      -x509 \
      -newkey rsa:4096 \
      -nodes \
      -days 3650 \
      -keyout "$key" \
      -out "$cert" \
      -subj "/CN=$host" \
      -addext ${lib.escapeShellArg "subjectAltName=DNS:${config.networking.hostName},DNS:localhost,IP:${cfg.httpHost}"}

    chown ${cfg.user}:${cfg.group} "$key" "$cert"
    chmod 0640 "$key" "$cert"
  '';
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
        ExecStart = generateCertificate;
        User = "root";
        Group = "root";
      };
    };
  };
}
