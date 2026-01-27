# SPDX-License-Identifier: Apache-2.0
# NFS client support
{ ... }:
{
  services.rpcbind.enable = true;
  services.nfs.server.enable = false;
}
