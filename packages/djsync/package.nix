{pkgs}:
pkgs.python313Packages.buildPythonPackage rec {
  pname = "djsync";
  version = "1.4.3-rc.1";
  format = "setuptools";

  src = pkgs.fetchFromGitHub {
    owner = "Pikkol0";
    repo = "djsync";
    rev = "9d7ecdd7fd291a856ea689f4bdcd65c1c4ec865c";
    hash = "sha256-1obLZSjB2Bgzz4f0nnUyfxLuhalqxrAyqRcKRaXz/lU=";
  };

  # upstream has no pyproject.toml/setup.py (it is a Windows PyInstaller app);
  # generate the minimal setuptools metadata needed to install the library.
  postPatch = ''
    cat > setup.py <<'EOF'
    from setuptools import find_packages, setup

    setup(
        name="djsync",
        version="1.4.3",
        description="Rekordbox USB export without Rekordbox",
        packages=find_packages(include=["djsync", "djsync.*"]),
        python_requires=">=3.9",
        install_requires=[
            "Pillow>=10",
            "mutagen>=1.47",
            "numpy>=1.24",
            "rapidfuzz>=3.6",
            "requests>=2.31",
            "sqlcipher3-wheels>=0.5.5",
        ],
    )
    EOF
  '';

  propagatedBuildInputs = with pkgs.python313Packages; [
    mutagen
    numpy
    pillow
    rapidfuzz
    requests
    sqlcipher3
  ];

  doCheck = false;
  pythonImportsCheck = [
    "djsync.db"
    "djsync.core.genre_playlists"
  ];

  meta = with pkgs.lib; {
    description = "Rekordbox USB export library and audio analysis, usable from Python";
    homepage = "https://github.com/Pikkol0/djsync";
    license = licenses.gpl3Only;
    maintainers = [];
    platforms = platforms.unix;
  };
}
