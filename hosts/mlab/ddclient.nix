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
    # single source of truth = ssh.marcel.cool. A only: the module's usev6 default asks
    # api6.ipify.org for the outbound source address, which IPv6PrivacyExtensions makes a
    # rotating temporary address - publishing it churns the AAAA daily and leaks the exact
    # address privacy extensions exist to hide. Rotation itself stays on for invidious egress.
    domains = ["ssh.marcel.cool" "marcel.cool"];
    usev4 = "webv4, webv4=ifconfig.me";
    usev6 = "";
    ssl = true;
  };

  users.users.ddclient = {
    isSystemUser = true;
    group = "ddclient";
  };
  users.groups.ddclient = {};

  systemd.services.ddclient.after = ["nss-user-lookup.target"];
}
