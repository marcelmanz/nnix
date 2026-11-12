{
  config,
  pkgs,
  lib,
  inputs,
  services,
  ...
}: let
  workspace = "/var/lib/agent-sandbox";
  agentUid = 2000;
  bridgePython = pkgs.python3.withPackages (ps: [ps.aiohttp]);
  bridgeDir = pkgs.runCommand "agent-bridge" {} ''
    mkdir $out
    cp ${./agent-sandbox/bridge.py} $out/bridge.py
    cp ${./agent-sandbox/index.html} $out/index.html
  '';
  agentSandbox = pkgs.writeShellApplication {
    name = "agent-sandbox";
    text = ''
      sudo nixos-container start agent >/dev/null 2>&1 || true
      exec sudo nixos-container run agent -- runuser -l agent -c "$*"
    '';
  };
in {
  users.users.agent-sandbox = {
    isSystemUser = true;
    uid = agentUid;
    group = "agent-sandbox";
  };
  users.groups.agent-sandbox.gid = agentUid;

  sops.templates."agent-sandbox.env" = {
    content = "SYNTHETIC_API_KEY=${config.sops.placeholder.synthetic_api_key}\n";
    owner = "agent-sandbox";
    mode = "0400";
    restartUnits = ["container@agent.service"];
  };

  systemd.tmpfiles.rules = [
    "d ${workspace} 0750 agent-sandbox agent-sandbox -"
    "d ${workspace}/.sessions 0750 agent-sandbox agent-sandbox -"
    "d ${workspace}/.pi 0750 agent-sandbox agent-sandbox -"
    "d ${workspace}/.pi/agent 0750 agent-sandbox agent-sandbox -"
    "L+ ${workspace}/.pi/agent/models.json - - - - ${inputs.dots}/.pi/agent/models.json"
  ];

  systemd.services.agent-bridge = {
    description = "Web bridge to pi in the agent sandbox";
    after = ["container@agent.service"];
    wantedBy = ["multi-user.target"];
    path = ["/run/current-system/sw"];
    environment = {
      STATE_DIR = "/var/lib/agent-bridge";
      PORT = toString services.agent.port;
    };
    serviceConfig = {
      ExecStart = "${bridgePython}/bin/python ${bridgeDir}/bridge.py";
      StateDirectory = "agent-bridge";
      Restart = "on-failure";
    };
  };

  networking.nat = {
    enable = true;
    internalInterfaces = ["ve-agent"];
  };

  networking.firewall.extraCommands = ''
    # The sandbox gets the internet only: no LAN, no podman/pia bridges, no host services.
    iptables -C FORWARD -i ve-agent -d 192.168.0.0/16 -j DROP 2>/dev/null \
      || iptables -I FORWARD 1 -i ve-agent -d 192.168.0.0/16 -j DROP
    iptables -C FORWARD -i ve-agent -d 10.0.0.0/8 -j DROP 2>/dev/null \
      || iptables -I FORWARD 1 -i ve-agent -d 10.0.0.0/8 -j DROP
    iptables -C FORWARD -i ve-agent -d 172.16.0.0/12 -j DROP 2>/dev/null \
      || iptables -I FORWARD 1 -i ve-agent -d 172.16.0.0/12 -j DROP
  '';

  systemd.services."container@agent".serviceConfig = {
    MemoryMax = "8G";
    CPUQuota = "400%";
    TasksMax = 4096;
  };

  containers.agent = {
    autoStart = false;
    privateNetwork = true;
    hostAddress = "10.233.1.1";
    localAddress = "10.233.1.2";
    bindMounts = {
      "/workspace" = {
        hostPath = workspace;
        isReadOnly = false;
      };
      "/run/agent.env" = {
        hostPath = config.sops.templates."agent-sandbox.env".path;
        isReadOnly = true;
      };
    };
    config = {...}: {
      system.stateVersion = config.system.stateVersion;
      networking.useHostResolvConf = lib.mkForce false;
      networking.nameservers = ["1.1.1.1" "8.8.8.8"];
      services.resolved.enable = false;

      users.users.agent = {
        isNormalUser = true;
        uid = agentUid;
        home = "/workspace";
        createHome = false;
      };

      environment.systemPackages = with pkgs; [
        pi-coding-agent
        git
        gnumake
        gcc
        python3
        nodejs
        ripgrep
        fd
        jq
        curl
      ];
      environment.variables = {
        PI_SKIP_VERSION_CHECK = "1";
        PI_TELEMETRY = "0";
      };
      environment.loginShellInit = ''
        set -a
        . /run/agent.env
        set +a
      '';
    };
  };

  environment.systemPackages = [agentSandbox];
}
