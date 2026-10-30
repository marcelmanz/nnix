{
  pkgs,
  crane,
}: let
  craneLib = crane.mkLib pkgs;
  call = name: import ../packages/${name}/package.nix {inherit craneLib pkgs;};
in
  final: prev: {
    lsv = call "lsv";
    ink-md = call "ink-md";
    audio-select = call "audio-select";
    rff = call "rff";
    pulseaudio-next-output = call "pulseaudio-next-output";
    git-commit-search = call "git-commit-search";
    reedline-bash = call "reedline-bash";
  }
