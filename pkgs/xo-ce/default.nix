# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra Package - Built from source using yarn2nix
# This package builds the complete Xen Orchestra application (xo-server + xo-web)
# from a Yarn v1 workspace monorepo with Turbo build orchestration.

{ pkgs, lib, xoSrc }:

pkgs.mkYarnPackage rec {
  pname = "xen-orchestra";
  version = "unstable-${lib.substring 0 8 (xoSrc.rev or "unknown")}";

  src = xoSrc;

  # Root-level package.json and yarn.lock for the workspace
  packageJSON = "${xoSrc}/package.json";
  yarnLock = "${xoSrc}/yarn.lock";

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
  preBuild = ''
    # SMB handler fix: prevent execa rejection on mount.cifs version check
    # Allows mount.cifs to fail gracefully without rejecting the promise
    sed -i "s/execa\.sync('mount\.cifs', \['-V'\])/execa.sync('mount.cifs', ['-V'], { reject: false })/" \
      @xen-orchestra/fs/src/index.js

    # TypeScript generic fix for VtsSelect component
    # Adds 'as any' to suppress TypeScript strict mode errors
    sed -i "s/h(VtsSelect, { accent: 'brand', id })/h(VtsSelect as any, { accent: 'brand', id })/" \
      @xen-orchestra/web-core/lib/tables/column-definitions/select-column.ts

    # Initialize git repository (required by some build tools)
    git init
    git config user.email "builder@localhost"
    git config user.name "Nix Builder"
    git add -A
    git commit -m "build snapshot"
  '';

  buildPhase = ''
    export HOME=$TMPDIR
    export TURBO_TELEMETRY_DISABLED=1
    export NODE_ENV=production

    # Install dependencies with network access (mkYarnPackage handles workspace setup)
    yarn install --prefer-offline --no-audit

    # Run Turbo-based build for xo-server, xo-web, and plugins
    # This filters and builds only the necessary packages
    yarn build
  '';

  postInstall = ''
    # Patch native modules with FUSE library paths
    # Ensures .node files can find libfuse at runtime
    find $out -name "*.node" -type f | while read nodefile; do
      patchelf --set-rpath "${lib.makeLibraryPath [ pkgs.fuse pkgs.fuse3 pkgs.stdenv.cc.cc.lib ]}" \
        "$nodefile" 2>/dev/null || true
    done

    # Verify critical build artifacts exist
    xoBaseDir="$out/libexec/xen-orchestra"

    # Check xo-server CLI (accepts both .mjs and .js)
    if [ ! -f "$xoBaseDir/packages/xo-server/dist/cli.mjs" ] && \
       [ ! -f "$xoBaseDir/packages/xo-server/dist/cli.js" ]; then
      echo "ERROR: xo-server CLI not found at $xoBaseDir/packages/xo-server/dist/" >&2
      exit 1
    fi

    # Check xo-web build output
    if [ ! -f "$xoBaseDir/packages/xo-web/dist/index.html" ]; then
      echo "ERROR: xo-web build output not found at $xoBaseDir/packages/xo-web/dist/" >&2
      exit 1
    fi

    echo "XOA package build successful!"
  '';

  distPhase = "true";  # Skip default dist phase

  meta = with lib; {
    description = "Xen Orchestra Community Edition - Web interface for XCP-ng and XenServer";
    homepage = "https://github.com/vatesfr/xen-orchestra";
    license = licenses.agpl3Plus;
    platforms = platforms.linux;
    maintainers = [];
  };
}
