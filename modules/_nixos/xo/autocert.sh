#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
umask 077

: "${NIXOA_XO_TLS_CERT:?NIXOA_XO_TLS_CERT must be set}"
: "${NIXOA_XO_TLS_KEY:?NIXOA_XO_TLS_KEY must be set}"
: "${NIXOA_XO_TLS_DIR:?NIXOA_XO_TLS_DIR must be set}"
: "${NIXOA_XO_HOSTNAME:?NIXOA_XO_HOSTNAME must be set}"
: "${NIXOA_XO_HTTP_HOST:?NIXOA_XO_HTTP_HOST must be set}"
: "${NIXOA_XO_USER:?NIXOA_XO_USER must be set}"
: "${NIXOA_XO_GROUP:?NIXOA_XO_GROUP must be set}"

mkdir -p "$NIXOA_XO_TLS_DIR"
chmod 0755 "$NIXOA_XO_TLS_DIR"

if [ -s "$NIXOA_XO_TLS_KEY" ] \
  && [ -s "$NIXOA_XO_TLS_CERT" ] \
  && openssl x509 -checkend 0 -noout -in "$NIXOA_XO_TLS_CERT" 2>/dev/null
then
  exit 0
fi

openssl req \
  -x509 \
  -newkey rsa:4096 \
  -nodes \
  -days 3650 \
  -keyout "$NIXOA_XO_TLS_KEY" \
  -out "$NIXOA_XO_TLS_CERT" \
  -subj "/CN=$NIXOA_XO_HOSTNAME" \
  -addext "subjectAltName=DNS:$NIXOA_XO_HOSTNAME,DNS:localhost,IP:$NIXOA_XO_HTTP_HOST"

chown "$NIXOA_XO_USER:$NIXOA_XO_GROUP" "$NIXOA_XO_TLS_KEY" "$NIXOA_XO_TLS_CERT"
chmod 0640 "$NIXOA_XO_TLS_KEY" "$NIXOA_XO_TLS_CERT"
