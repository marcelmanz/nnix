{ pkgs, ... }:

{
  # Proxied via proxy.nix (services.insta -> insta.marcel.cool, port 3022).

  # Upstream (codeberg.org/irelephant/kittygram) publishes no container
  # image, so build it from a checkout in /var/lib/kittygram. podman build is
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
        git clone --depth=1 https://codeberg.org/irelephant/kittygram.git "$src"
      else
        git -C "$src" pull --ff-only
      fi
      git -C "$src" lfs install --local
      git -C "$src" lfs pull
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
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.podman}/bin/podman network inspect kittygram-net >/dev/null 2>&1 || ${pkgs.podman}/bin/podman network create kittygram-net'";
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
