{
  craneLib,
  pkgs,
  inputs,
}:
craneLib.buildPackage {
  pname = "reedline-bash";
  version = "unstable-${builtins.substring 0 8 inputs.reedline-bash.lastModifiedDate}";
  src = inputs.reedline-bash;
}
