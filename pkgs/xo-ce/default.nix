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
  # Fetch SageMath fuse-native fork (uses system libfuse3 instead of bundled binary)
  fuseNativeFork = pkgs.fetchFromGitHub {
    owner = "sagemathinc";
    repo = "fuse-native";
    rev = "master";
    sha256 = "sha256-+qOaBDbsgLPF3nq1PmSpdcmdgjGS5RCooyBaGG+mNTw=";
  };

in
pkgs.buildNpmPackage {
  pname = "xo-ce";
  version = "unstable-${lib.substring 0 8 (xoSrc.rev or "unknown")}";

  src = xoSrc;

  nativeBuildInputs = with pkgs; [
    python3           # Required by node-gyp for native module compilation
    pkg-config        # Find fuse3 headers/libs via .pc file
    git               # Required by build tools
    patchelf          # Patch fuse-native rpath to find libfuse3
  ];

  buildInputs = with pkgs; [
    fuse3             # libfuse3.so.3 + headers for fuse-native
    zlib              # Compression library
    libpng            # Image processing
    stdenv.cc.cc.lib  # C++ standard library
  ];

  # buildNpmPackage expects npmDepsHash (hash of all npm dependencies)
  # Update this after first build with actual hash from error message
  npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  # Environment variables for pkg-config and node-gyp
  PKG_CONFIG_PATH = "${pkgs.fuse3.dev}/lib/pkgconfig";
  npm_config_nodedir = "${pkgs.nodejs_20}";

  # Initialize git repository (required by some build tools)
  # Copy local package-lock.json into unpacked source
  postUnpack = ''
    cd "$sourceRoot"

    # Copy local package-lock.json (from nixoa-vm/pkgs/xo-ce/)
    cp ${./package-lock.json} ./package-lock.json

    git init
    git config user.email "builder@localhost"
    git config user.name "Nix Builder"
    git add -A
    git commit -m "build snapshot" || true
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

  # Configure phase: Replace fuse-native with SageMath fork
  # buildNpmPackage automatically installs node_modules before this phase runs
  preConfigure = ''
    # Replace bundled fuse-native with SageMath fork (uses system libfuse3)
    if [ -d "node_modules/fuse-native" ]; then
      echo "Replacing fuse-native npm package with SageMath fork..."
      rm -rf node_modules/fuse-native
      cp -r ${fuseNativeFork} node_modules/fuse-native
      chmod -R +w node_modules/fuse-native

      # Build the native module against system libfuse3 via pkg-config
      cd node_modules/fuse-native
      export HOME=$TMPDIR
      npm run install || npx node-gyp rebuild
      cd ../..
    fi
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

    # Patch fuse-native rpath to find system libfuse3.so.3 at runtime
    FUSE_NATIVE_BINARY=$(find $out/libexec/xen-orchestra/node_modules/fuse-native -name "*.node" 2>/dev/null | head -1)
    if [ -n "$FUSE_NATIVE_BINARY" ]; then
      echo "Patching fuse-native rpath: $FUSE_NATIVE_BINARY"
      ${pkgs.patchelf}/bin/patchelf --set-rpath "${lib.makeLibraryPath [ pkgs.fuse3 pkgs.stdenv.cc.cc.lib ]}" \
        "$FUSE_NATIVE_BINARY"

      # Verify linkage
      echo "Verifying fuse-native linkage:"
      ${pkgs.binutils}/bin/readelf -d "$FUSE_NATIVE_BINARY" | grep -i "libfuse" || echo "  (library not directly linked, may use dlopen)"
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
