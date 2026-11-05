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
      rev = "5afe34c5f3adddcb850b8e329b64b822795640e9";
      hash = "sha256-lb92aox3t5F0QZ+742XdxmTMOZ0QuwSwobW8OhozTIc=";
    };

    npmDepsHash = "sha256-LT21Cy7SLw0Mudr1CxIMEX4IOfb1U1pQ+eTysKfYDhs=";

    postPatch = ''
      substituteInPlace next.config.mjs --replace-fail \
        "value: 'www.offtiktok.com'," \
        "value: 'www.offtiktok.com',
                },
                {
                  type: 'host',
                  value: 'offtiktok.marcel.cool',"
    '';

    env = {
      NEXT_PUBLIC_API_URL = "https://offtiktok-api.marcel.cool";
      NEXT_INTERNAL_API_URL = "http://127.0.0.1:3010";
      NEXT_TELEMETRY_DISABLED = "1";
    };

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/offtiktok $out/bin
      cp -r .next public package.json next.config.mjs node_modules $out/share/offtiktok/
      cat > $out/bin/offtiktok <<EOF
      #!${runtimeShell}
      cd $out/share/offtiktok
      exec ${nodejs}/bin/node node_modules/next/dist/bin/next start -H 127.0.0.1 -p 3010
      EOF
      chmod +x $out/bin/offtiktok
      runHook postInstall
    '';

    passthru.port = 3010;
  }
