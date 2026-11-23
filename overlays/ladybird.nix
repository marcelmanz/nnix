{inputs}: final: prev: let
  llvmLibcPort = builtins.fromJSON (builtins.readFile "${inputs.ladybird}/Meta/CMake/vcpkg/overlay-ports/llvm-libc/vcpkg.json");
  llvm-libc-headers = final.stdenvNoCC.mkDerivation {
    pname = "llvm-libc-headers";
    version = llvmLibcPort.version-string;
    src = final.fetchFromGitHub {
      owner = "llvm";
      repo = "llvm-project";
      rev = llvmLibcPort.version-string;
      sparseCheckout = ["libc"];
      # Goes stale whenever upstream bumps the llvm-libc vcpkg port.
      hash = "sha256-rYvY2rTNwA3Ovy3y/hI3nTp9v8kJbhxB2gseLcZ5vWA=";
    };
    installPhase = ''
      cd libc
      find hdr include shared src/__support src/string/memory_utils -name '*.h' \
        -exec install -Dm644 {} $out/include/llvm-libc/{} \;
    '';
  };
in {
  ladybird = prev.ladybird.overrideAttrs (old: {
    src = inputs.ladybird;
    version = "0-unstable-${builtins.substring 0 8 inputs.ladybird.lastModifiedDate}";
    cargoDeps = final.rustPlatform.importCargoLock {lockFile = "${inputs.ladybird}/Cargo.lock";};
    buildInputs = old.buildInputs ++ [llvm-libc-headers];
    # Only Ladybird's patched FFmpeg defines it, to work around an NVIDIA AV1 Vulkan decode bug.
    env = old.env // {NIX_CFLAGS_COMPILE = "-DAV_HWACCEL_FLAG_LADYBIRD_CLEAR_UNUSED_REF_FRAME_MVS=0";};
    # Upstream now locates pdf.js via FindPDFJS.cmake, so nixpkgs' ResourceFiles.cmake patch no longer applies.
    postPatch = builtins.replaceStrings ["substituteInPlace UI/cmake/ResourceFiles.cmake"] ["true"] old.postPatch;
    preConfigure =
      old.preConfigure
      + ''
        cmakeFlagsArray+=("-DPDFJS_DIR=$PWD/pdfjs")
      '';
  });
}
