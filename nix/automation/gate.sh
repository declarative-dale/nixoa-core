#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

test "${CHECK_RESULT:?}" = success
if test "${INSTALLER_REQUIRED:?}" = true; then
  test "${PLAN_RESULT:?}" = success
  if test "${SHOULD_BUILD:?}" = true; then
    test "${BUILD_RESULT:?}" = success
  else
    test "${BUILD_RESULT:?}" = skipped
  fi
else
  test "${PLAN_RESULT:?}" = skipped
  test "${BUILD_RESULT:?}" = skipped
fi
