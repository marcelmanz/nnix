{
  craneLib,
  pkgs,
}:
craneLib.buildPackage {
  pname = "ferrosonic";
  version = "0.8.3";
  doCheck = false;
  src = pkgs.fetchzip {
    url = "https://crates.io/api/v1/crates/ferrosonic/0.8.3/download";
    extension = "tar.gz";
    sha256 = "sha256-9ROrh8X12R3VQAVNUOQlSLH9THtvkhtGuIPeLSis8x8=";
  };
  nativeBuildInputs = [pkgs.pkg-config pkgs.makeWrapper];
  buildInputs = [pkgs.openssl];
  postInstall = ''
    wrapProgram $out/bin/ferrosonic \
      --suffix PATH : ${pkgs.lib.makeBinPath [pkgs.mpv pkgs.pipewire]}
  '';
}
