#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

: "${NIXOA_CI_PLAN_SCHEMA:?NIXOA_CI_PLAN_SCHEMA must point to the route plan schema}"
plan=${1:?Usage: nixoa-ci-validate-plan PLAN.json}

check-jsonschema --quiet --schemafile "$NIXOA_CI_PLAN_SCHEMA" "$plan"
