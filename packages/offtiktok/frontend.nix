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
        "redirects: async () => {" \
        "redirects: async () => { return [];"
      substituteInPlace "src/app/post/[id]/page.tsx" --replace-fail \
        "container md:rounded-2xl md:m-auto" \
        "container md:m-auto"
      substituteInPlace "src/app/post/[id]/page.module.scss" \
        --replace-fail "max-width: 550px;" "height: 100dvh !important; width: calc(100dvh * 9 / 16) !important; max-width: 100vw !important;" \
        --replace-fail "aspect-ratio: 6/9;" "aspect-ratio: 9/16;"
      substituteInPlace src/components/VideoPlayer/index.tsx --replace-fail \
        "isPanoramic ? 'object-contain' : 'object-cover'" \
        "'object-contain'"
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
