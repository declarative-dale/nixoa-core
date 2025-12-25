# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra Package - Built using Dream2Nix
# This package builds the complete Xen Orchestra application (xo-server + xo-web)
# from a Yarn v1 workspace monorepo with Turbo build orchestration.
#
# Dream2Nix handles all dependency fetching, workspace resolution, and permission
# issues automatically, providing a pure and reproducible build without sandboxing workarounds.

{ pkgs, lib, xoSrc, dream2nix }:

dream2nix.lib.mkDerivation rec {
  pname = "xo-ce";
  version = "unstable-${lib.substring 0 8 (xoSrc.rev or "unknown")}";

  src = xoSrc;

  # Use the nodejs-package-lock source type for yarn.lock
  sourceType = "nodejs-package-lock";

  # Dream2Nix will auto-detect yarn.lock in the source root
  # No need to manually specify lock files

  # Native build inputs
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

  postUnpack = ''
    # Initialize git repository (required by some build tools)
    cd "$sourceRoot"
    git init
    git config user.email "builder@localhost"
    git config user.name "Nix Builder"
    git add -A
    git commit -m "build snapshot" || true
  '';

  configurePhase = ''
    export HOME=$TMPDIR
    export TURBO_TELEMETRY_DISABLED=1
    export NODE_ENV=production
  '';

  installPhase = ''
    mkdir -p $out/libexec/xen-orchestra

    # Copy built artifacts and dependencies
    cp -r packages $out/libexec/xen-orchestra/ || true
    cp -r node_modules $out/libexec/xen-orchestra/ || true
    cp -r @xen-orchestra $out/libexec/xen-orchestra/ || true
    cp yarn.lock $out/libexec/xen-orchestra/ || true
    cp package.json $out/libexec/xen-orchestra/ || true

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
