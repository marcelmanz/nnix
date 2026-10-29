{
  config,
  inputs,
  pkgs,
  services,
  ...
}: {
  sops.secrets."nitter_sessions" = {};

  services.nitter = {
    enable = true;
    package = inputs.nixpkgsNitter.legacyPackages.${pkgs.stdenv.hostPlatform.system}.nitter;
    # jsonl, one {"kind":"cookie",...} session per line (nix run .#nitter-session)
    sessionsFile = config.sops.secrets."nitter_sessions".path;
    # 6379 is livekit's; own instance on 6380
    redisCreateLocally = false;
    cache.redisPort = 6380;

    server = {
      address = "127.0.0.1";
      port = services.nitter.port;
      hostname = "nitter.marcel.cool";
      https = true;
      title = "nitter";
    };
  };

  # module doesn't order nitter against the redis it needs; first start loses the race
  systemd.services.nitter = {
    after = ["redis-nitter.service"];
    requires = ["redis-nitter.service"];
  };

  services.redis.servers.nitter = {
    enable = true;
    port = 6380;
  };
}
