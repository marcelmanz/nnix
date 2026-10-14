# nixpkgs' authelia 4.39.28 has a stale pnpmDepsHash (lockfile churned
# upstream after the bump). Override with the hash the fetcher actually
# computes. ponytail: delete this overlay once nixpkgs fixes the hash.
final: prev:
let
  web = prev.callPackage "${prev.path}/pkgs/by-name/au/authelia/web.nix" {};
in {
  authelia = prev.authelia.override {
    authelia-web = web.overrideAttrs (old: {
      pnpmDeps = old.pnpmDeps.overrideAttrs (_: {
        outputHash = "sha256-zIaVEjbh/LIQMqnryrgVm+46GP+9gM91WCMyAqeDnaA=";
      });
    });
  };
}
