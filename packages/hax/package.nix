{pkgs}:
pkgs.stdenv.mkDerivation {
  pname = "hax";
  version = "0.6.0";
  src = pkgs.fetchFromGitHub {
    owner = "OleksandrChekhovskyi";
    repo = "hax";
    rev = "v0.6.0";
    hash = "sha256-9b5L8sn3HCK7p9aUSHNPfi5cySWOcy7qPReuBwtwMPA=";
  };
  nativeBuildInputs = with pkgs; [meson ninja pkg-config];
  buildInputs = with pkgs; [curl jansson];
}
