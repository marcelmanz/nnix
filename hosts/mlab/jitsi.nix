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
      # Jicofo authentication password - must match the focus user in Prosody
      jicofo.password = "focuspass123";
      # Configure authentication via extraConfig (injects into config.js)
      extraConfig = ''
        // Enable authentication - guests can join, login required to create meetings
        config.authentication = {
          enabled: true,
          type: 'internal'
        };
        config.enableAnonymousUsers = true;
        // Only authenticated users can create rooms
        config.enableUserCreation = false;
      '';
    };

    interfaceConfig = {
      SHOW_JITSI_WATERMARK = false;
      SHOW_WATERMARK_FOR_GUESTS = false;
    };

    # Disable the module's automatic prosody config
    prosody.enable = false;
  };

  # Manually configure Prosody for Jitsi with proper authentication
  services.prosody = {
    enable = true;
    # Disable XEP-0423 compliance checks
    xmppComplianceSuite = false;
    # Add prosody to jitsi-meet group to access SSL keys
    group = "jitsi-meet";
    # Enable required modules for Jitsi (HTTP, BOSH, WebSocket)
    extraModules = ["http" "bosh" "websocket" "c2s"];

    # Complete Prosody configuration for Jitsi
    extraConfig = lib.mkAfter ''
      -- Main domain - requires authentication to create rooms
      VirtualHost "${hostName}" {
        authentication = "internal_hashed";
        storage = "internal";
        ssl = {
          certificate = "/var/lib/jitsi-meet/jitsi-meet.crt";
          key = "/var/lib/jitsi-meet/jitsi-meet.key";
        };
      }

      -- Auth domain for authenticated users
      VirtualHost "auth.${hostName}" {
        authentication = "internal_hashed";
        storage = "internal";
        ssl = {
          certificate = "/var/lib/jitsi-meet/jitsi-meet.crt";
          key = "/var/lib/jitsi-meet/jitsi-meet.key";
        };
      }

      -- Guest domain - anonymous users can join but not create
      VirtualHost "guest.${hostName}" {
        authentication = "anonymous";
        storage = "internal";
        ssl = {
          certificate = "/var/lib/jitsi-meet/jitsi-meet.crt";
          key = "/var/lib/jitsi-meet/jitsi-meet.key";
        };
      }

      -- Recorder domain
      VirtualHost "recorder.${hostName}" {
        authentication = "internal_plain";
        storage = "internal";
        ssl = {
          certificate = "/var/lib/jitsi-meet/jitsi-meet.crt";
          key = "/var/lib/jitsi-meet/jitsi-meet.key";
        };
      }

      -- Focus component
      Component "focus.${hostName}" "client_proxy" {
        authentication = "internal_plain";
      }

      -- Conference MUC
      Component "conference.${hostName}" "muc" {
        restrict_room_creation = true;
        storage = "internal";
        admins = { "focus@auth.${hostName}" };
      }

      -- Internal auth MUC
      Component "internal.auth.${hostName}" "muc" {
        restrict_room_creation = true;
        storage = "internal";
        admins = { "focus@auth.${hostName}" };
      }

      -- Lobby MUC
      Component "lobby.${hostName}" "muc" {
        restrict_room_creation = true;
        storage = "internal";
        admins = { "focus@auth.${hostName}" };
      }

      -- Breakout rooms MUC
      Component "breakout.${hostName}" "muc" {
        restrict_room_creation = true;
        storage = "internal";
        admins = { "focus@auth.${hostName}" };
      }

      -- Other Jitsi components
      Component "jigasi.${hostName}" "client_proxy";
      Component "speakerstats.${hostName}" "speakerstats_component" {
        muc_component = "conference.${hostName}";
      }
      Component "conferenceduration.${hostName}" "conference_duration_component" {
        muc_component = "conference.${hostName}";
      }
      Component "endconference.${hostName}" "end_conference" {
        muc_component = "conference.${hostName}";
      }
      Component "avmoderation.${hostName}" "av_moderation_component" {
        muc_component = "conference.${hostName}";
      }
      Component "metadata.${hostName}" "room_metadata_component" {
        muc_component = "conference.${hostName}";
        breakout_rooms_component = "breakout.${hostName}";
      }
    '';
  };

  # Opens UDP 10000 (media) and TCP 4443 (media fallback) for the videobridge.
  services.jitsi-videobridge.openFirewall = true;

  # Create admin user for Jitsi authentication
  systemd.services.jitsi-admin-user = {
    after = ["prosody.service"];
    wants = ["prosody.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      # Create admin user if it doesn't exist
      if ! prosodyctl register jitsi.marcel.cool admin "JitsiAdmin2026!"; then
        echo "User already exists or registration failed"
      fi
      if ! prosodyctl register auth.jitsi.marcel.cool admin "JitsiAdmin2026!"; then
        echo "Auth user already exists or registration failed"
      fi
    '';
  };

  # The jitsi-meet module creates this nginx vhost itself. Reuse the existing
  # wildcard *.marcel.cool cert instead of requesting a per-host certificate.
  services.nginx.virtualHosts.${hostName} = {
    enableACME = lib.mkForce false;
    useACMEHost = "marcel.cool";
    forceSSL = true;
  };
}
