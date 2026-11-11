final: prev: let
  python = prev.python3.override {
    self = python;
    packageOverrides = pyfinal: pyprev: {
      chromadb = pyprev.chromadb.overridePythonAttrs (old: {
        buildInputs = (old.buildInputs or []) ++ [prev.sqlite];
        preBuild = (old.preBuild or "") + "unset JEMALLOC_OVERRIDE\n";
      });
      primp = pyprev.primp.overridePythonAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or []) ++ [prev.pkg-config];
        buildInputs = (old.buildInputs or []) ++ [prev.zstd];
        preBuild = (old.preBuild or "") + "unset AWS_LC_SYS_USE_SYSTEM\n";
      });
    };
  };
in {
  open-webui = prev.open-webui.override {python3Packages = python.pkgs;};
}
