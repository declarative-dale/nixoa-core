# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra Package - Built using buildNpmPackage for reproducible builds
# This package builds the complete Xen Orchestra application (xo-server + xo-web)
# from a Yarn v1 workspace monorepo with Turbo build orchestration.
#
# Uses buildNpmPackage with package-lock.json for fully sandboxed, offline dependency fetching.
# No --no-sandbox flag required. Reproducible builds with binary cache support.
#
# FUSE integration: Replaces bundled fuse-native with SageMath fork that uses
# system libfuse3 instead of vendored binaries (better security, ARM64 support).
#
# NOTE: Uses local package-lock.json from nixoa-vm/pkgs/xo-ce/package-lock.json
# Generate with: cd xen-orchestra && npm install --package-lock-only
# Then copy package-lock.json to this directory.

{ pkgs, lib, xoSrc }:

let
  # Merge xoSrc with local package-lock.json
  # This ensures package-lock.json is included in the source before buildNpmPackage processes it
  srcWithLockfile = pkgs.runCommand "xo-src-with-lockfile" {} ''
    cp -r ${xoSrc} $out
    chmod -R +w $out
    cp ${./package-lock.json} $out/package-lock.json
  '';

in
pkgs.buildNpmPackage {
  pname = "xo-ce";
  version = "unstable-${lib.substring 0 8 (xoSrc.rev or "unknown")}";

  src = srcWithLockfile;

  nativeBuildInputs = with pkgs; [
    python3           # Required by node-gyp for native module compilation
    pkg-config        # Find library headers/libs via .pc files
    git               # Required by build tools
  ];

  buildInputs = with pkgs; [
    fuse3             # libfuse3 for FUSE native module
    zlib              # Compression library
    libpng            # Image processing
    stdenv.cc.cc.lib  # C++ standard library
  ];

  # buildNpmPackage expects npmDepsHash (hash of all npm dependencies)
  # Update this after first build with actual hash from error message
  npmDepsHash = "sha256-c3aqGWyZZn3dAgTVf1B2ncrkox6AlU5NlwRLCzR4+3M=";

  # Environment variables for pkg-config and node-gyp
  PKG_CONFIG_PATH = "${pkgs.fuse3.dev}/lib/pkgconfig";
  npm_config_nodedir = "${pkgs.nodejs_20}";

  # Initialize git repository (required by some build tools)
  postUnpack = ''
    cd "$sourceRoot"
    git init
    git config user.email "builder@localhost"
    git config user.name "Nix Builder"
  '';

  # Apply source patches before build
  postPatch = ''
    # SMB handler fix: prevent execa rejection on mount.cifs version check
    sed -i "s/execa\.sync('mount\.cifs', \['-V'\])/execa.sync('mount.cifs', ['-V'], { reject: false })/" \
      @xen-orchestra/fs/src/index.js || true

    # TypeScript generic fix for VtsSelect component
    sed -i "s/h(VtsSelect, { accent: 'brand', id })/h(VtsSelect as any, { accent: 'brand', id })/" \
      @xen-orchestra/web-core/lib/tables/column-definitions/select-column.ts || true
  '';

  # Build phase: Run Turbo-based build for xo-server, xo-web, and plugins
  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR
    export TURBO_TELEMETRY_DISABLED=1
    export TURBO_FORCE=true
    export NODE_ENV=production
    export TURBO_CACHE_DIR=$TMPDIR/.turbo

    mkdir -p $TURBO_CACHE_DIR

    # Run build with Turbo (node_modules already installed)
    npm run build

    runHook postBuild
  '';

  # Install phase: Copy built artifacts to $out
  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/xen-orchestra

    # Copy workspace packages
    cp -r packages $out/libexec/xen-orchestra/ || true
    cp -r @xen-orchestra $out/libexec/xen-orchestra/ || true
    cp -r @vates $out/libexec/xen-orchestra/ || true

    # Copy node_modules with compiled native modules
    cp -r node_modules $out/libexec/xen-orchestra/

    # Copy metadata
    cp package-lock.json $out/libexec/xen-orchestra/ || true
    cp package.json $out/libexec/xen-orchestra/

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

    runHook postInstall
  '';

  doDist = false;

  meta = with lib; {
    description = "Xen Orchestra Community Edition - Web interface for XCP-ng and XenServer";
    homepage = "https://github.com/vatesfr/xen-orchestra";
    license = licenses.agpl3Plus;
    platforms = platforms.linux;
    maintainers = [];
  };
}
