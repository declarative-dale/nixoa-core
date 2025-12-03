#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
journalctl -u xo-build -u xo-server -u redis-xo -e -f
