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
, nodejs_24
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
    nodejs_24
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

  # Make sure Yarn does NOT drop devDependencies (vite/vue-tsc live there).
  # Leave NODE_ENV unset to avoid conflicts with build environment defaults.
  YARN_PRODUCTION = "false";
  NPM_CONFIG_PRODUCTION = "false";

  # If you hit `EPERM: operation not permitted, chmod ...` in sandbox,
  # enableChmodSanitizer will strip setuid/setgid bits during extraction.
  NODE_OPTIONS = lib.optionalString enableChmodSanitizer "--require ${yarnChmodSanitize}";

  # Flags for yarn install (and sometimes reused by build hooks).
  yarnInstallFlags = [
    "--offline"
    "--frozen-lockfile"
    "--non-interactive"
    "--ignore-engines"
    "--production=false"
  ];

  # Keep the old name too (some nixpkgs versions/hooks read yarnFlags).
  yarnFlags = yarnInstallFlags;

  # After yarnConfigHook has populated node_modules, patch bin shebangs thoroughly.
  # This fixes the common case where node_modules/.bin/* are symlinks to scripts
  # that still have "#!/usr/bin/env node" and fail as "not found" under /bin/sh.
  postConfigure = ''
    patchShebangs node_modules
  '';

  # Ensure workspace root tools are visible in all Turbo/Yarn workspace tasks.
  # Turbo runs builds from each package directory, and some build-time CLIs
  # (vite/vue-tsc) are hoisted to the workspace root.
  preBuild = ''
    # Export workspace root .bin onto PATH so Turbo tasks can find hoisted CLIs.
    export PATH="$PWD/node_modules/.bin:$PATH"

    # Make sure the web package can resolve its hoisted build tools even if the
    # runner only prepends *package-local* node_modules/.bin.
    for pkg in "@xen-orchestra/web" "xo-web"; do
      if [ -d "$pkg" ]; then
        mkdir -p "$pkg/node_modules/.bin"
        for tool in vite vue-tsc; do
          if [ -e "$PWD/node_modules/.bin/$tool" ] && [ ! -e "$pkg/node_modules/.bin/$tool" ]; then
            ln -s "$PWD/node_modules/.bin/$tool" "$pkg/node_modules/.bin/$tool"
          fi
        done
      fi
    done

    echo "Checking build-time web tooling exists..."
    ls -l node_modules/.bin | grep -E '^(lrwx|-) .* (vite|vue-tsc)' || true
    test -e node_modules/.bin/vite || (echo "ERROR: vite not found in node_modules/.bin" && exit 1)
    test -e node_modules/.bin/vue-tsc || (echo "ERROR: vue-tsc not found in node_modules/.bin" && exit 1)
  '';

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
    makeWrapper ${nodejs_24}/bin/node $out/bin/xo-server \
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
