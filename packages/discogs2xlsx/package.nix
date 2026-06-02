{pkgs}:
pkgs.python3Packages.buildPythonApplication {
  pname = "discogs2xlsx";
  version = "0.4.0";
  format = "setuptools";
  src = pkgs.fetchFromGitHub {
    owner = "fscm";
    repo = "discogs2xlsx";
    rev = "v0.4.0";
    sha256 = "0l23751lir6bckrn51xfximvnqqrr5wx5a0sylm1h999l8s1lyjn";
  };
  postPatch = ''
    substituteInPlace discogs2xlsx/__main__.py \
      --replace-fail "options.all['apikey']" "options.all['token']"
  '';
  propagatedBuildInputs = with pkgs.python3Packages; [
    progress
    requests
    xlsxwriter
  ];
  doCheck = false;
}
