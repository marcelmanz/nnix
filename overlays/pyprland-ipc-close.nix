final: prev: {
  pyprland = prev.pyprland.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace pyprland/ipc.py \
          --replace-fail 'from contextlib import asynccontextmanager' \
            'from contextlib import asynccontextmanager, suppress' \
          --replace-fail '        await writer.wait_closed()' \
            '        with suppress(OSError):
                    await writer.wait_closed()'
      '';
  });
}
