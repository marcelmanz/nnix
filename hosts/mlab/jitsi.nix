{lib, ...}: let
  hostName = "jitsi.marcel.cool";
in {
  services.jitsi-meet = {
    enable = true;
    inherit hostName;

    config = {
      enableWelcomePage = true;
      prejoinPageEnabled = true;
      defaultLang = "en";
    };

    interfaceConfig = {
      SHOW_JITSI_WATERMARK = false;
      SHOW_WATERMARK_FOR_GUESTS = false;
    };
  };

  # Opens UDP 10000 (media) and TCP 4443 (media fallback) for the videobridge.
  services.jitsi-videobridge.openFirewall = true;

  # The jitsi-meet module creates this nginx vhost itself. Reuse the existing
  # wildcard *.marcel.cool cert instead of requesting a per-host certificate.
  services.nginx.virtualHosts.${hostName} = {
    enableACME = lib.mkForce false;
    useACMEHost = "marcel.cool";
    forceSSL = true;
  };
}
