# ostui fork with --vim-keys (https://git.sr.ht/~marcelmanz/ostui, branch vim-keybinds).
final: prev: {
  ostui = prev.ostui.overrideAttrs (old: {
    version = "1.3.10-vim";
    src = prev.fetchFromSourcehut {
      owner = "~marcelmanz";
      repo = "ostui";
      rev = "b1aa002adba32b04864f5fa9ba5a467a6d22007b";
      hash = "sha256-w6Q+tO+huSTIsythzDEpGS5l25FuIalddqe434d5RRw=";
    };
  });
}
