# open-webui 0.12.3 pins mcp==1.27.2 and imports APIs mcp 2 removed; nixpkgs' pythonRelaxDeps
# hides the pin, so it crashes on start. ponytail: delete once nixpkgs builds it against mcp_1.
final: prev: let
  python = prev.python3.override {
    self = python;
    packageOverrides = pyfinal: pyprev: {mcp = pyfinal.mcp_1;};
  };
in {
  open-webui = prev.open-webui.override {python3Packages = python.pkgs;};
}
