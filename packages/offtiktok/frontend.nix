{
  fetchFromGitHub,
  buildNpmPackage,
  nodejs,
  runtimeShell,
}: let
  # Browser reaches the API at its public URL (baked into the client bundle);
  # SSR calls itself on loopback (PORT must match the systemd unit's port).
in
  buildNpmPackage {
    pname = "offtiktok";
    version = "0.1.0";

    src = fetchFromGitHub {
      owner = "marcelmanz";
      repo = "offtiktok";
      rev = "e2fbc1c0eadeb49ac269b6fbdb8ee3e9052887c0";
      hash = "sha256-bCg/5CeUmxZoZM00JcdfRd0K37Qh1zAmS8SFkOoUkkg=";
    };

    npmDepsHash = "sha256-LT21Cy7SLw0Mudr1CxIMEX4IOfb1U1pQ+eTysKfYDhs=";

    env = {
      NEXT_PUBLIC_API_URL = "https://offtiktok-api.marcel.cool";
      NEXT_INTERNAL_API_URL = "http://127.0.0.1:3010";
      NEXT_TELEMETRY_DISABLED = "1";
    };

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/offtiktok $out/bin
      cp -r .next public package.json next.config.mjs node_modules $out/share/offtiktok/
      rm -rf $out/share/offtiktok/.next/cache
      ln -s /var/cache/offtiktok $out/share/offtiktok/.next/cache
      cat > $out/bin/offtiktok <<EOF
      #!${runtimeShell}
      export NEXT_INTERNAL_API_URL=http://127.0.0.1:3010
      cd $out/share/offtiktok
      exec ${nodejs}/bin/node node_modules/next/dist/bin/next start -H 127.0.0.1 -p 3010
      EOF
      chmod +x $out/bin/offtiktok
      runHook postInstall
    '';

    passthru.port = 3010;
  }
