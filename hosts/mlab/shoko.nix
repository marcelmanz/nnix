{
  _config,
  pkgs,
  lib,
  ...
}: let
  # Shoko's AVDumpHelper (v5.3.1, AVDumpHelper.cs) looks for
  # `<SHOKO_HOME>/AVDump/AVDump3CL.dll` and on Linux execs `dotnet <that dll>`.
  # It has no bundled download URL, so it throws "Unable to install AVDump3
  # automatically" unless the dll is already there. The nix `avdump3` package
  # ships the full flat distribution in share/avdump3/.
  #
  # AVDumpHelper.PrepareAVDump also calls ReplaceNet6(), which rewrites
  # AVDump3CL.runtimeconfig.json 6.0->8.0 when it `Contains("6.0")`. A store
  # path is read-only, so that write throws UnauthorizedAccessException and
  # fires the "AVDump failed to install" event (even though the dump still
  # runs). Pre-patch the runtimeconfig to 8.0 at build time so the Contains
  # check is false and Shoko never tries to write -> symlink is safe.
  # ponytail: net6.0 tfm + rollForward:major runs fine under dotnet 8.0; the
  # patch is exactly what Shoko itself does at runtime.
  avdump3-net8 = pkgs.runCommand "avdump3-net8" {} ''
    mkdir -p $out/share
    cp -r ${pkgs.avdump3}/share/avdump3 $out/share/avdump3
    chmod -R u+w $out
    sed -i 's/6\.0/8.0/g' $out/share/avdump3/AVDump3CL.runtimeconfig.json
  '';
in {
  services.shoko = {
    enable = true;
    openFirewall = true;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/media/anime 2775 root media -"
    "d /var/lib/media/downloads/anime 2775 root media -"
  ];

  # ponytail: path option merges with enableDefaultPath (mkAfter), so coreutils
  # etc. stay on PATH; no regression.
  systemd.services.shoko = {
    path = [pkgs.dotnet-runtime];
    preStart = ''
      rm -rf /var/lib/shoko/AVDump
      ln -sfn ${avdump3-net8}/share/avdump3 /var/lib/shoko/AVDump
    '';

    serviceConfig = {
      SupplementaryGroups = ["media"];
      ReadWritePaths = ["/var/lib/media"];
      UMask = lib.mkForce "0002";
    };
  };
}
