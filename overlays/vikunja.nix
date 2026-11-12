{inputs}: final: prev: let
  src = inputs.vikunja;
  version = "2.8.0-unstable-${builtins.substring 0 8 src.lastModifiedDate}";
  # Both hashes go stale on every `nix flake update vikunja`.
  frontend = prev.vikunja.frontend.overrideAttrs (old: rec {
    inherit src version;
    sourceRoot = "source/frontend";
    pnpmDeps = final.fetchPnpmDeps {
      inherit (old) pname;
      inherit src version sourceRoot;
      pnpm = final.pnpm_12;
      fetcherVersion = 5;
      hash = "sha256-6R88EwrN35KVNK4ln58bp+XTUNfaPxMeCqZutbPJYe4=";
    };
  });
in {
  vikunja-git = prev.vikunja.overrideAttrs {
    inherit src version frontend;
    vendorHash = "sha256-IWowYwcpP9AOPf+n5a5LD6f7hbPxyDBA6FB9X1IsbrE=";
  };

  vikunja-nightly = prev.runCommand "vikunja-nightly" {meta.mainProgram = "vikunja";} ''
    install -Dm755 ${inputs.vikunja-nightly}/vikunja-unstable-linux-amd64 $out/bin/vikunja
  '';
}
