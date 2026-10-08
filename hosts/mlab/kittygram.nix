{ pkgs, ... }:

{
  # Proxied via proxy.nix (services.insta -> insta.marcel.cool, port 3022).

  # Built from marcelmanz's fork (SearXNG-backed search), no image published upstream. podman build is
  # layer-cached; a no-change rebuild costs seconds. To force an update:
  # `systemctl start kittygram-image` then restart podman-kittygram.
  systemd.tmpfiles.rules = [ "d /var/lib/kittygram 0755 root root -" ];

  systemd.services.kittygram-image = {
    description = "Build the kittygram container image from source";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ git git-lfs podman ];
    serviceConfig.Type = "oneshot";
    script = ''
      src=/var/lib/kittygram
      if [ ! -d "$src/.git" ]; then
        git clone --depth=1 https://codeberg.org/marcelmanz/kittygram.git "$src"
      else
        git -C "$src" pull --ff-only
      fi
      git -C "$src" lfs install --local
      git -C "$src" lfs pull
      # ponytail: lapis >=1.17 dropped types.id from its sqlite schema, so
      # upstream's own Dockerfile fails at 'lapis migrate'. Swap in integer -
      # both tables it touches declare their own PRIMARY KEYs explicitly, so
      # the column type is cosmetic. Delete this once upstream upstream fixes
      # migrations.lua.
      sed -i 's/types\.id/types.integer/g' "$src/migrations.lua"
      podman build -t localhost/kittygram:latest "$src"
    '';
  };

  # Named network so kittygram reaches valkey by container name (aardvark-dns),
  # same pattern as seafile.nix.
  systemd.services.podman-network-kittygram = {
    description = "Create Podman network for kittygram";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # --subnet keeps the gateway IP stable so SEARXNG_URL/RESOLVER below
      # survive a network recreate.
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.podman}/bin/podman network inspect kittygram-net >/dev/null 2>&1 || ${pkgs.podman}/bin/podman network create --subnet=10.89.2.0/24 kittygram-net'";
    };
  };

  virtualisation.oci-containers.containers = {
    kittygram-valkey = {
      image = "docker.io/valkey/valkey:latest";
      extraOptions = [ "--network=kittygram-net" ];
    };
    kittygram = {
      image = "localhost/kittygram:latest";
      dependsOn = [ "kittygram-valkey" ];
      ports = [ "127.0.0.1:3022:80" ];
      environment = {
        REDIS_HOST = "kittygram-valkey";
        REDIS_PORT = "6379";
        # Gateway IP, not host.containers.internal: openresty's resolver
        # appends the dns.podman search domain to it and aardvark NXDOMAINs.
        SEARXNG_URL = "http://10.89.2.1:8084";
        RESOLVER = "10.89.2.1";
        ABOUT_MESSAGE = "Muerte al capitalismo ostias ya";
      };
      extraOptions = [ "--network=kittygram-net" ];
    };
  };

  systemd.services.podman-kittygram = {
    after = [ "kittygram-image.service" "podman-network-kittygram.service" ];
    requires = [ "kittygram-image.service" "podman-network-kittygram.service" ];
  };
  systemd.services.podman-kittygram-valkey = {
    after = [ "podman-network-kittygram.service" ];
    requires = [ "podman-network-kittygram.service" ];
  };
}
