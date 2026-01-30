# SPDX-License-Identifier: Apache-2.0
# Input validation helpers
{ lib, ... }:
{
  # Path validation helper
  validatePath =
    path:
    assert lib.assertMsg (builtins.isString path && path != "") "Path must be a non-empty string";
    path;

  # Port validation helper
  validatePort =
    port:
    assert lib.assertMsg (
      builtins.isInt port && port > 0 && port < 65536
    ) "Port must be between 1-65535";
    port;
}
