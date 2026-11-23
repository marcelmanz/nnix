final: prev: {
  # pyprland shows scratchpads with `movetoworkspacesilent <workspace name>`, but
  # Hyprland's Lua selectors don't resolve names set via default_name, so the
  # move spawns a second workspace with the same name. Target the id instead.
  pyprland = prev.pyprland.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace pyprland/plugins/scratchpads/transitions.py \
          --replace-fail 'move_commands: list[str] = []' \
            'move_commands: list[str] = []; target_wrkspc = str(monitor["activeWorkspace"]["id"]) if wrkspc == monitor["activeWorkspace"]["name"] and monitor["activeWorkspace"].get("id", 0) > 0 else wrkspc' \
          --replace-fail 'movetoworkspacesilent {wrkspc},address' 'movetoworkspacesilent {target_wrkspc},address'
      '';
  });
}
