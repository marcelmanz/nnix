{pkgs}:
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "retrosmart-cursors";
  version = "3.0";
  src = pkgs.fetchFromGitHub {
    owner = "mdomlop";
    repo = "retrosmart-x11-cursors";
    rev = version;
    sha256 = "1rsilsv21ah1qn1f2048nl367sfqqsr7z3scj6wilr6rlqfgqjmi";
  };
  nativeBuildInputs = with pkgs; [imagemagick xcursorgen];
  # imagemagick's montage aborts without a usable font, even though it draws no text
  postPatch = ''
    substituteInPlace cursors.mk --replace-fail 'montage $^' 'montage -font ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf $^'
  '';
  # upstream only ships 32/36 px; add pixel-doubled 64/72 px for HiDPI
  preBuild = ''
    make png
    for png in png/*/32-*.png png/*/36-*.png; do
      name=$(basename "$png")
      size=''${name%%-*}
      magick "$png" -filter point -resize 200% "$(dirname "$png")/$((size * 2))-''${name#*-}"
    done
    for spec in src/*.in; do
      awk '{ print; size = $1 * 2; $1 = size; $2 *= 2; $3 *= 2; sub(/^[0-9]+-/, size "-", $4); print }' "$spec" > "$spec.tmp"
      mv "$spec.tmp" "$spec"
    done
  '';
  installPhase = ''
    mkdir -p $out/share/icons
    for theme in src/*.theme; do
      cp -r "$(basename "$theme" .theme)" $out/share/icons/
    done
  '';
}
