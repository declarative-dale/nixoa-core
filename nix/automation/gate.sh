#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

test "${VALIDATE_RESULT:?}" = success
if test "${INSTALLER_REQUIRED:?}" = true; then
  if test "${SHOULD_BUILD:?}" = true; then
    test "${BUILD_RESULT:?}" = success
  else
    test "${BUILD_RESULT:?}" = skipped
  fi
else
  test "${BUILD_RESULT:?}" = skipped
fi
