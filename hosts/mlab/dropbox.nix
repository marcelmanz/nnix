# Drop-box: passwordless shared folder for an external recipient.
{...}: {
  users.groups.dropbox = {};

  users.users.share_guest = {
    isNormalUser = true;
    extraGroups = ["dropbox"];
    openssh.authorizedKeys.keys = [
      "sh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICt4VE3AHMG49lg2uwTft1vIROkUYjID9SGIuofbABcv jufegam@gmail.com"
    ];
  };

  users.users.dev.extraGroups = ["dropbox"];

  # Setgid folder: files dropped by dev inherit group `dropbox`, which
  # share_guest is a member of, so the guest always has read access.
  # Home dir group=dropbox, mode 0750 so dev can traverse into the subfolder.
  # ponytail: relies on umask 022 (group-readable files). If dev's umask is
  # tighter, upgrade to a default ACL: setfacl -d -m g:dropbox:rX <folder>.
  systemd.tmpfiles.rules = [
    "d /home/share_guest 0750 share_guest dropbox -"
    "d /home/share_guest/dropbox 2770 share_guest dropbox -"
  ];
}
