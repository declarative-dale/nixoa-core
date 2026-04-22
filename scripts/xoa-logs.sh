#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

redis_unit="$(nixoa_redis_service_name)"

exec journalctl -u xo-build -u xo-server -u "${redis_unit%.service}" -e -f
