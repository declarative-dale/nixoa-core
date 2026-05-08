{
  pkgs,
  xenOrchestraCe,
}:
pkgs.runCommandLocal (xenOrchestraCe.name or "xen-orchestra-ce") {
  meta = xenOrchestraCe.meta or {};
  passthru = xenOrchestraCe.passthru or {};
} ''
  mkdir -p "$out"

  for path in ${xenOrchestraCe}/*; do
    ln -s "$path" "$out/$(basename "$path")"
  done

  if [ -f ${xenOrchestraCe}/bin/xo-server ] \
    && grep -q 'packages/xo-server/bin/xo-server' ${xenOrchestraCe}/bin/xo-server; then
    rm -f "$out/bin"
    mkdir -p "$out/bin"

    for path in ${xenOrchestraCe}/bin/*; do
      ln -s "$path" "$out/bin/$(basename "$path")"
    done

    rm -f "$out/bin/xo-server"
    cp ${xenOrchestraCe}/bin/xo-server "$out/bin/xo-server"
    substituteInPlace "$out/bin/xo-server" \
      --replace-fail 'packages/xo-server/bin/xo-server' 'packages/xo-server/dist/cli.mjs'
  fi
''
