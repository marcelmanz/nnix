{ config, pkgs, ... }:

let
  notesDir = "/var/lib/notes";
in
{
  systemd.tmpfiles.rules = [
    "d ${notesDir} 0770 root root -"
  ];

  # Proxied via proxy.nix (services.notes -> notes.marcel.cool, behind Authelia).
  # Port 3000 is open-webui's, hence 3021.
  virtualisation.oci-containers.containers.silverbullet = {
    image = "zefhemel/silverbullet:latest";
    ports = [ "127.0.0.1:3021:3000" ];
    volumes = [ "${notesDir}:/space" ];
  };

  systemd.services.notes-git-sync = {
    description = "Auto-commit and sync SilverBullet notes";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.git pkgs.openssh ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      WorkingDirectory = notesDir;
    };

    script = ''
      export GIT_SSH_COMMAND="ssh -i ${config.sops.secrets.github_ssh_key.path} -o StrictHostKeyChecking=no"

      git config --global user.name "SilverBullet (mlab)"
      git config --global user.email "bot@marcel.cool"
      git config --global pull.rebase true

      if [ ! -d ".git" ]; then
        git clone git@github.com:marcelmanz/notes.git .
      fi

      git add .
      git diff-index --quiet HEAD || git commit -m "Auto-commit from mlab Web UI"
      git pull origin main
      git push origin main
    '';
  };

  systemd.timers.notes-git-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "5m";
    };
  };
}
