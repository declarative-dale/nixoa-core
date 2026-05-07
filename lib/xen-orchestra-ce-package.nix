{xenOrchestraCe}:
xenOrchestraCe.overrideAttrs (oldAttrs: {
  postFixup =
    (oldAttrs.postFixup or "")
    + ''
      if [ -f "$out/bin/xo-server" ] && grep -q 'packages/xo-server/bin/xo-server' "$out/bin/xo-server"; then
        substituteInPlace "$out/bin/xo-server" \
          --replace-fail 'packages/xo-server/bin/xo-server' 'packages/xo-server/dist/cli.mjs'
      fi
    '';
})
