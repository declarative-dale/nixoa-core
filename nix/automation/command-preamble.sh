#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

if [[ -n ${NIXOA_CI_PATH_PREFIX:-} ]]; then
  export PATH="$NIXOA_CI_PATH_PREFIX:$PATH"
fi
