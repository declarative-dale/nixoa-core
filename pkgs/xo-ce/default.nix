# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra Package - Built from source using Yarn
# This package builds the complete Xen Orchestra application (xo-server + xo-web)
# from a Yarn v1 workspace monorepo with Turbo build orchestration.

{ pkgs, lib, xoSrc }:

pkgs.stdenv.mkDerivation rec {
  pname = "xen-orchestra";
  version = "unstable-${lib.substring 0 8 (xoSrc.rev or "unknown")}";

  src = xoSrc;

  # Enable network access for yarn to fetch packages from npm registry
  __noChroot = true;
  SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  nativeBuildInputs = with pkgs; [
    nodejs_20
    yarn
    python3
    pkg-config
    git
    patchelf
  ];

  buildInputs = with pkgs; [
    fuse
    fuse3
    zlib
    libpng
    stdenv.cc.cc.lib
  ];

  # Apply patches to source before build
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

    # Install dependencies
    export HOME=$TMPDIR
    export TURBO_TELEMETRY_DISABLED=1
    export NODE_ENV=production

    yarn install --no-audit
  '';

  buildPhase = ''
    export HOME=$TMPDIR
    export TURBO_TELEMETRY_DISABLED=1
    export NODE_ENV=production

    # Run Turbo-based build for xo-server, xo-web, and plugins
    yarn build
  '';

  installPhase = ''
    mkdir -p $out/libexec/xen-orchestra

    # Copy built artifacts and dependencies
    cp -r packages $out/libexec/xen-orchestra/
    cp -r node_modules $out/libexec/xen-orchestra/
    cp -r @xen-orchestra $out/libexec/xen-orchestra/ || true
    cp yarn.lock $out/libexec/xen-orchestra/
    cp package.json $out/libexec/xen-orchestra/

    # Patch native modules with FUSE library paths
    find $out -name "*.node" -type f | while read nodefile; do
      patchelf --set-rpath "${lib.makeLibraryPath [ pkgs.fuse pkgs.fuse3 pkgs.stdenv.cc.cc.lib ]}" \
        "$nodefile" 2>/dev/null || true
    done

    # Verify critical build artifacts exist
    if [ ! -f "$out/libexec/xen-orchestra/packages/xo-server/dist/cli.mjs" ] && \
       [ ! -f "$out/libexec/xen-orchestra/packages/xo-server/dist/cli.js" ]; then
      echo "ERROR: xo-server CLI not found!" >&2
      exit 1
    fi

    if [ ! -f "$out/libexec/xen-orchestra/packages/xo-web/dist/index.html" ]; then
      echo "ERROR: xo-web build output not found!" >&2
      exit 1
    fi

    echo "XOA package build successful!"
  '';

  meta = with lib; {
    description = "Xen Orchestra Community Edition - Web interface for XCP-ng and XenServer";
    homepage = "https://github.com/vatesfr/xen-orchestra";
    license = licenses.agpl3Plus;
    platforms = platforms.linux;
    maintainers = [];
  };
}
