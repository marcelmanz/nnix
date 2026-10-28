final: prev: {
  # hyprland 0.56.1 requires glaze in the 7.x range (find_package(glaze 7...<8)),
  # but nixpkgs currently ships glaze 8.0.0, so cmake falls back to FetchContent,
  # which fails in the sandboxed build (no network/git). Pin glaze back to 7.2.0
  # for hyprland only, until nixpkgs bumps hyprland's glaze pin.
  hyprland = prev.hyprland.override {
    glaze = prev.glaze.overrideAttrs (old: {
      version = "7.2.0";
      patches = [];
      src = final.fetchFromGitHub {
        owner = "stephenberry";
        repo = "glaze";
        tag = "v7.2.0";
        hash = "sha256-f3NVRi3SXKo42hn0WCw7JsOK3EkdOVJIcuzhPorKjFY=";
      };
    });
  };
}
