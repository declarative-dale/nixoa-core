# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra Community Edition (XO-CE) — deterministic Yarn v1 build.
#
# Why this structure:
# - Xen Orchestra uses a Yarn v1 workspace monorepo.
# - Nixpkgs provides fetchYarnDeps + yarn{Config,Build}Hook for Yarn v1.
#   This lets us build fully offline (sandboxed) with a fixed-output yarn cache.
#
# Optional workaround:
# - Some npm tarballs contain files with setuid/setgid bits.
# - In Nix sandboxes, chmod() of those bits can fail (EPERM) due to nosuid.
# - enableChmodSanitizer makes Node strip those bits during yarn extraction.

{ lib
, stdenv
, fetchYarnDeps
, yarn
, yarnConfigHook
, yarnBuildHook
, writableTmpDirAsHomeHook
, nodejs_20
, esbuild
, git
, python3
, pkg-config
, makeWrapper
, libpng
, zlib
, fuse3

, xoSrc

# Enabled by default; disable if needed by passing `enableChmodSanitizer = false;`.
, enableChmodSanitizer ? true
, yarnChmodSanitize ? ./yarn-chmod-sanitize.js
, ...
}:

stdenv.mkDerivation rec {
  pname = "xo-ce";
  version = "unstable-${builtins.substring 0 8 xoSrc.rev}";

  src = xoSrc;

  # Fixed-output offline mirror for Yarn.
  # Update the hash with: nix build .#xo-ce (then replace with actual hash).
  yarnOfflineCache = fetchYarnDeps {
    yarnLock = "${src}/yarn.lock";
    hash = "sha256-3vt/oIJ3JF2+0lGftq1IKckKoWVA1qNZZsl/bhRQ4Eo=";
  };

  nativeBuildInputs = [
    writableTmpDirAsHomeHook

    # Yarn v1 and hooks
    yarn
    yarnConfigHook
    yarnBuildHook

    # Needed for executing package.json scripts
    nodejs_20
    esbuild

    # Some scripts expect git to exist (and it's cheap)
    git

    # Native addons
    python3
    pkg-config

    # Runtime entrypoint
    makeWrapper
  ];

  buildInputs = [
    fuse3
    zlib
    libpng
    stdenv.cc.cc.lib
  ];

  # Keep builds quiet/deterministic.
  HUSKY = "0";
  CI = "1";

  # CRITICAL: XO's web build needs devDependencies (vite, vue-tsc, etc.)
  # If NODE_ENV=production here, yarn skips devDependencies → build fails
  NODE_ENV = "development";
  NPM_CONFIG_PRODUCTION = "false";
  YARN_PRODUCTION = "false";

  # Optional: run compilation in production mode after deps are installed
  preBuild = ''
    export NODE_ENV=production
  '';

  # If you hit `EPERM: operation not permitted, chmod ...` in sandbox,
  # enableChmodSanitizer will strip setuid/setgid bits during extraction.
  NODE_OPTIONS = lib.optionalString enableChmodSanitizer "--require ${yarnChmodSanitize}";

  # Flags passed to yarn install/build via nixpkgs yarn hooks.
  yarnFlags = [
    "--offline"
    "--frozen-lockfile"
    "--non-interactive"
    "--ignore-engines"
    "--production=false"
  ];

  # Conditional patching: only patches if file exists and has expected pattern.
  # This makes updates to xoSrc.rev survive upstream fixes without breaking the build.
  postPatch = ''
    # Patch 1: SMB handler needs createReadStream
    if [ -f packages/xo-server/src/xo-mixins/storage/smb.js ] \
      && grep -q "const { join } = require('path')" packages/xo-server/src/xo-mixins/storage/smb.js; then
      substituteInPlace packages/xo-server/src/xo-mixins/storage/smb.js \
        --replace-fail "const { join } = require('path')" \
                       "const { join } = require('path'); const { createReadStream } = require('fs')"
    fi

    # Patch 2: Fix missing createReadStream import in FS module
    if [ -f @xen-orchestra/fs/src/index.js ] \
      && grep -q "const { asyncIterableToStream }" @xen-orchestra/fs/src/index.js \
      && ! grep -q "createReadStream" @xen-orchestra/fs/src/index.js; then
      substituteInPlace @xen-orchestra/fs/src/index.js \
        --replace-fail "const { asyncIterableToStream } = require('./_asyncIterableToStream')" \
                       "const { createReadStream } = require('node:fs');\nconst { asyncIterableToStream } = require('./_asyncIterableToStream')"
    fi
  '';

  # yarnConfigHook runs the yarn install using the offline cache.
  # yarnBuildHook runs: yarn --offline build
  # Both happen automatically, no manual phases needed!

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/xen-orchestra
    mkdir -p $out/bin

    # Keep symlinks as symlinks (important for yarn workspaces).
    cp -a packages node_modules package.json yarn.lock $out/libexec/xen-orchestra/

    # Some revisions include these top-level workspace scopes.
    if [ -d @xen-orchestra ]; then cp -a @xen-orchestra $out/libexec/xen-orchestra/; fi
    if [ -d @vates ]; then cp -a @vates $out/libexec/xen-orchestra/; fi

    # Optional docs
    if [ -f README.md ]; then cp -a README.md $out/libexec/xen-orchestra/; fi
    if [ -f LICENSE ]; then cp -a LICENSE $out/libexec/xen-orchestra/; fi

    # Runtime entrypoint (using upstream's bin wrapper)
    makeWrapper ${nodejs_20}/bin/node $out/bin/xo-server \
      --chdir $out/libexec/xen-orchestra \
      --add-flags "packages/xo-server/bin/xo-server"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Xen Orchestra Community Edition (built from source)";
    homepage = "https://xen-orchestra.com";
    license = licenses.agpl3Only;
    platforms = platforms.linux;
    mainProgram = "xo-server";
  };
}
