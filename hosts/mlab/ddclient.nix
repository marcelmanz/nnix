{
  config,
  _lib,
  _services,
  ...
}: {
  sops.secrets."cloudflare_ddclient_token" = {
    owner = "ddclient";
    group = "ddclient";
  };

  services.ddclient = {
    enable = true;
    interval = "5min";
    protocol = "cloudflare";
    zone = "marcel.cool";
    username = "token";
    passwordFile = config.sops.secrets.cloudflare_ddclient_token.path;
    # single source of truth = ssh.marcel.cool (A only - this host has no working IPv6 route,
    # so usev6 just timed out on api6.ipify.org every run, ~4min+ per cycle across all domains)
    domains = ["ssh.marcel.cool" "marcel.cool"];
    usev4 = "webv4, webv4=ifconfig.me";
    ssl = true;
  };

  users.users.ddclient = {
    isSystemUser = true;
    group = "ddclient";
  };
  users.groups.ddclient = {};

  systemd.services.ddclient.after = ["nss-user-lookup.target"];
}
