final: prev: {
  mautrix-whatsapp = prev.mautrix-whatsapp.overrideAttrs (old: {
    src = final.fetchFromGitHub {
      owner = "marcelmanz";
      repo = "whatsapp";
      rev = "8fe4ad77e6286277607f70537d40225c085fe33d";
      sha256 = "sha256-QUIMr7VlA7d7xjEYEPIPhLX7NwONcVgp5lRFh1tX0BY=";
    };
    vendorHash = "sha256-WUJeI8lb7/YYqNzm0IMB/uCgdb5Mcz7bii2fsI4gOKc=";
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [final.pkg-config];
    buildInputs = (old.buildInputs or []) ++ [final.libopus final.opusfile final.libogg final.soxr];
  });
}
