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
  SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

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
  '';

  buildPhase = ''
    export HOME=$TMPDIR
    export TURBO_TELEMETRY_DISABLED=1
    export NODE_ENV=production

    echo "Fetching yarn dependencies..."
    yarn install --frozen-lockfile

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
