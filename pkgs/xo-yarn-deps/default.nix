# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra Yarn Dependencies Cache
#
# This derivation pre-fetches all npm dependencies for the XOA monorepo.
# It can be built independently and cached, making subsequent builds pure.
#
# Usage:
#   nix build .#xo-yarn-deps --no-sandbox  # First time (requires network)
#   # After building once, Nix caches the result
#   # Main xo-ce build will use the cached version (fully sandboxed)

{ pkgs, lib, xoSrc }:

pkgs.stdenv.mkDerivation {
  pname = "xo-ce-yarn-deps";
  version = "unstable-${lib.substring 0 8 (xoSrc.rev or "unknown")}";

  src = xoSrc;

  # Only this derivation needs network access for initial fetch
  __noChroot = true;

  # Configure SSL/TLS for Node.js yarn
  SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  NODE_EXTRA_CA_CERTS = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  nativeBuildInputs = with pkgs; [
    nodejs_20
    yarn
    git
  ];

  phases = [ "unpackPhase" "patchPhase" "configurePhase" "buildPhase" ];

  # Apply patches to source before fetching (some packages might check for fixes)
  prePatch = ''
    # SMB handler fix: prevent execa rejection on mount.cifs version check
    sed -i "s/execa\.sync('mount\.cifs', \['-V'\])/execa.sync('mount.cifs', ['-V'], { reject: false })/" \
      @xen-orchestra/fs/src/index.js || true

    # TypeScript generic fix for VtsSelect component
    sed -i "s/h(VtsSelect, { accent: 'brand', id })/h(VtsSelect as any, { accent: 'brand', id })/" \
      @xen-orchestra/web-core/lib/tables/column-definitions/select-column.ts || true
  '';

  configurePhase = ''
    # Initialize git repository (required by some build tools)
    git init
    git config user.email "builder@localhost"
    git config user.name "Nix Builder"
    git add -A
    git commit -m "build snapshot" || true

    export HOME=$TMPDIR
    export TURBO_TELEMETRY_DISABLED=1
    export NODE_ENV=production
    export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    export NODE_EXTRA_CA_CERTS="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
  '';

  buildPhase = ''
    export HOME=$TMPDIR
    export TURBO_TELEMETRY_DISABLED=1
    export NODE_ENV=production
    export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    export NODE_EXTRA_CA_CERTS="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

    # Clear any cached yarn data to ensure clean extraction
    rm -rf $HOME/.cache/yarn 2>/dev/null || true

    # Allow all file permissions during extraction (Nix build uses restrictive umask)
    umask 0000

    echo "Fetching yarn dependencies..."
    echo "Using CA bundle from: $NODE_EXTRA_CA_CERTS"

    # Install dependencies with permission and script handling
    # --frozen-lockfile: Use exact versions from yarn.lock
    # --unsafe-perm: Allow chmod operations during extraction
    # --ignore-scripts: Skip post-install scripts (run during actual build)
    # --no-optional: Skip optional dependencies that may have permission issues
    yarn install --frozen-lockfile --unsafe-perm --ignore-scripts --no-optional

    echo "Dependencies fetched successfully!"
  '';

  installPhase = ''
    mkdir -p $out

    # Output cache for main build to use
    cp -r node_modules $out/
    cp yarn.lock $out/
    cp package.json $out/

    echo "Yarn dependencies cached to $out"
  '';

  meta = with lib; {
    description = "Pre-fetched npm dependencies for Xen Orchestra";
    license = licenses.agpl3Plus;
    platforms = platforms.linux;
  };
}
