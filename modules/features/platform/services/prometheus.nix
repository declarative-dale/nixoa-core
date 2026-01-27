# SPDX-License-Identifier: Apache-2.0
# Prometheus node exporter (optional)
{
  lib,
  ...
}:
{
  services.prometheus.exporters.node = {
    enable = lib.mkDefault false;
    port = 9100;
    openFirewall = false;

    enabledCollectors = [
      "conntrack"
      "diskstats"
      "entropy"
      "filefd"
      "filesystem"
      "loadavg"
      "meminfo"
      "netdev"
      "netstat"
      "stat"
      "time"
      "uname"
      "vmstat"
    ];
  };
}
