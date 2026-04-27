{
  craneLib,
  pkgs,
}:
craneLib.buildPackage {
  pname = "pulseaudio-next-output";
  version = "unstable-2025-09-04";
  nativeBuildInputs = with pkgs; [pkg-config];
  buildInputs = with pkgs; [pulseaudio];
  src = pkgs.fetchgit {
    url = "https://github.com/murlakatamenka/pulseaudio-next-output";
    rev = "e46ea275e17ec7e00edd1c9627f00c4b7134b012";
    sha256 = "sha256-GuZCop5hUWeBqEYQB3O+MnQVg3uve3pC4ZjLejDflUc=";
  };
  cargoVendorHash = "sha256-aWw3qZFizCIoYN8M0cpVkA1misOezHmGi/UxM+7/6Ok=";
}
