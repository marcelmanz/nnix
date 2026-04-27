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
    domains = ["ssh.marcel.cool"];
    usev4 = "webv4, webv4=ifconfig.me";
    usev6 = "webv6, webv6=api6.ipify.org";
    ssl = true;
  };

  users.users.ddclient = {
    isSystemUser = true;
    group = "ddclient";
  };
  users.groups.ddclient = {};

  systemd.services.ddclient.after = ["nss-user-lookup.target"];
}
