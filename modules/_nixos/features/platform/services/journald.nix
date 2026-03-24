# SPDX-License-Identifier: Apache-2.0
# Journald defaults
{ ... }:
{
  services.journald.extraConfig = ''
    # Persistent storage
    Storage=persistent

    # Disk usage limits
    SystemMaxUse=1G
    SystemMaxFileSize=100M

    # Retention
    MaxRetentionSec=30d

    # Forward to console for debugging
    ForwardToConsole=no

    # Compression
    Compress=yes
  '';
}
