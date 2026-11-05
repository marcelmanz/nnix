{
  fetchFromGitHub,
  fetchurl,
  buildNpmPackage,
  nodejs,
  ffmpeg,
  openssl,
  stdenv,
  autoPatchelfHook,
  zlib,
  runtimeShell,
}: let
  # Prisma's npm packages don't vendor the engines; their postinstall
  # downloads them from binaries.prisma.sh. Pinned to the engines commit
  # prisma 5.17.0 uses, placed where the postinstall would put them
  # (node_modules/@prisma/engines/), so everything runs offline.
  prismaEngines = stdenv.mkDerivation {
    pname = "prisma-engines";
    version = "5.17.0";
    dontUnpack = true;
    nativeBuildInputs = [autoPatchelfHook];
    buildInputs = [openssl zlib stdenv.cc.cc.lib];
    installPhase = let
      commit = "393aa359c9ad4a4bb28630fb5613f9c281cde053";
      base = "https://binaries.prisma.sh/all_commits/${commit}/debian-openssl-3.0.x";
    in ''
      mkdir -p $out
      gunzip -c ${
        fetchurl {
          url = "${base}/libquery_engine.so.node.gz";
          hash = "sha256-El11c5vX/NuOq7VCg1W1vgD1QAQ+a8H1swJolHr6sb0=";
        }
      } > $out/libquery_engine-debian-openssl-3.0.x.so.node
      gunzip -c ${
        fetchurl {
          url = "${base}/schema-engine.gz";
          hash = "sha256-mK1DP9ZNouoettVlVTqaQzns8w8cIRsotpaQ9ZEmmkE=";
        }
      } > $out/schema-engine-debian-openssl-3.0.x
      chmod +x $out/*
    '';
  };
  # Runs `prisma migrate deploy` (creates the sqlite db on first start,
  # no-op afterwards) before the server. DATABASE_URL comes from the
  # systemd unit and must point inside the unit's StateDirectory.
in
  buildNpmPackage {
    pname = "offtiktokapi";
    version = "1.0.0";

    src = fetchFromGitHub {
      owner = "marcelmanz";
      repo = "offtiktokapi";
      rev = "cfc02046d6d302bda82e44e73bd89ad2c8483bcf";
      hash = "sha256-proL/PadtWqP7wruNW/u/h8DG0JeLOOgLshbw/ED9Vk=";
    };

    npmDepsHash = "sha256-cb++RE1anojBm+W3xZzmR6DJ6CilZc+v0hIvUdXBAnw=";

    patches = [./fetch-post-from-page.patch];

    # postinstalls would download chromium (puppeteer, unused: only legacy/*)
    # and the ffmpeg binary (ffmpeg-static); both replaced below.
    npmFlags = ["--ignore-scripts"];

    preBuild = ''
      export PATH="${openssl}/bin:$PATH"
      cp ${prismaEngines}/* node_modules/@prisma/engines/
      chmod +x node_modules/@prisma/engines/*
      # these two env vars short-circuit prisma's engine download logic entirely
      export PRISMA_QUERY_ENGINE_LIBRARY="$PWD/node_modules/@prisma/engines/libquery_engine-debian-openssl-3.0.x.so.node"
      export PRISMA_SCHEMA_ENGINE_BINARY="$PWD/node_modules/@prisma/engines/schema-engine-debian-openssl-3.0.x"
      npx prisma generate
    '';

    buildPhase = ''
      runHook preBuild
      npx tsc
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/offtiktokapi $out/bin
      cp -r dist node_modules prisma package.json $out/share/offtiktokapi/
      # ffmpeg-static resolves its binary relative to node_modules/ffmpeg-static/
      ln -s ${ffmpeg}/bin/ffmpeg $out/share/offtiktokapi/node_modules/ffmpeg-static/ffmpeg
      ln -s ${ffmpeg}/bin/ffprobe $out/share/offtiktokapi/node_modules/ffmpeg-static/ffprobe
      cat > $out/bin/offtiktokapi <<EOF
      #!${runtimeShell}
      export PATH=${nodejs}/bin:${openssl}/bin:\$PATH
      # engines link libssl.so.3/libcrypto.so.3, which live in the nix store
      export LD_LIBRARY_PATH=\''${LD_LIBRARY_PATH:+\$LD_LIBRARY_PATH:}${openssl.out}/lib
      export PRISMA_QUERY_ENGINE_LIBRARY=$out/share/offtiktokapi/node_modules/@prisma/engines/libquery_engine-debian-openssl-3.0.x.so.node
      export PRISMA_SCHEMA_ENGINE_BINARY=$out/share/offtiktokapi/node_modules/@prisma/engines/schema-engine-debian-openssl-3.0.x
      $out/share/offtiktokapi/node_modules/.bin/prisma migrate deploy --schema $out/share/offtiktokapi/prisma/schema.prisma
      cd "\''${STATE_DIRECTORY:?}"
      exec ${nodejs}/bin/node $out/share/offtiktokapi/dist/index.js
      EOF
      chmod +x $out/bin/offtiktokapi
      runHook postInstall
    '';

    passthru.port = 2000;
  }
