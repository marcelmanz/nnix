{
  craneLib,
  pkgs,
}:
craneLib.buildPackage {
  pname = "ink-md";
  version = "0.15.0";
  src = pkgs.fetchFromGitHub {
    owner = "borghei";
    repo = "ink";
    rev = "v0.15.0";
    sha256 = "sha256-c2PK7+h4rZDb5eGPMwNwjI7D4tZH/gPCq73xT/8r5xE=";
  };
}
