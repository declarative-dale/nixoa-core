#!/usr/bin/env bash
set -euo pipefail
journalctl -u xo-build -u xo-server -u redis-xo -e -f
