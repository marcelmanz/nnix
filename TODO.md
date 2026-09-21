- [ ] Setup Anki Server in mlab
- [x] Fix Soulbeet
- [ ] Calibrate the live recording A/V offset
  - Go live, clap on camera, stop, open the mkv in /var/lib/media/shows and
    measure how far the sound lags the clap. Write the seconds into
    /var/lib/azuracast-live-record/offset (no rebuild needed).
  - Until it's set the recorder uses 0, so video runs ahead of the audio by
    darkice's 5s buffer plus whatever liquidsoap adds. The livedj page says
    "not calibrated" while the file is empty.
- [ ] Revisit 4K webcam when building the custom radio client
  - The BRIO does MJPG 2160p30 on SuperSpeed; publishing it costs 2.34 cores
    and 16 Mbit/s per viewer (both measured). The server side is fine - uplink
    has been seen at 896 Mbit/s - so the blocker is viewers, not mlab.
  - Blocked on adaptive bitrate: mediamtx forwards the single track ffmpeg
    pushes, no simulcast, so every viewer gets one bitrate and a phone on
    mobile data freezes rather than degrading. The custom client is where
    quality selection can live - either a second mediamtx path publishing
    1080p alongside 4K, or real simulcast via a WebRTC publish instead of
    the RTSP push.
  - Also check phone H.264 4K High profile hardware decode before committing.

- [ ] Point the router's DHCP at mlab for DNS (192.168.1.140)
  - Hairpin NAT is broken on the router: from the LAN the WAN IPv4
    79.116.21.243 refuses 80/443 (only 22 hairpins), so every *.marcel.cool
    name is unreachable over IPv4 from inside. Only the AAAA path works.
  - mlab's dnsmasq already answers 192.168.1.140 for the whole zone
    (address=/marcel.cool/192.168.1.140, deployed), but the router answers :53
    itself and hands itself out, so no LAN client ever asks mlab.
  - If the router supports a static DNS entry instead, marcel.cool ->
    192.168.1.140 fixes every LAN device without touching DHCP.

- [ ] Drop insertNameservers on the laptop (nixos/configuration.nix:178)
  - NetworkManager prepends 1.1.1.1/8.8.8.8, which overrides whatever DHCP
    hands out - so the router change above will not reach this machine.
  - Cannot simply become ["192.168.1.140" ...]: off-LAN every lookup would
    stall on an unreachable resolver first. Wants systemd-resolved split DNS
    routing only ~marcel.cool to 192.168.1.140, scoped to the home connection.

- [ ] Fix the ssh-ng://mlab build machine entry (nixos/configuration.nix:26)
  - Every nixos-rebuild prints "cannot build on 'ssh-ng://mlab': Could not
    resolve hostname mlab" and falls back to building locally. The mlab alias
    only exists in ~/.ssh/config and the nix daemon runs as root.
  - Either point the entry at ssh.marcel.cool or add the Host alias to root's
    ssh config.

- [x] Setup a radio

- [x] Setup an auto sync of bandcamp buys

- [x] Setup SOPS properly
  - [x] Setup passwords for vps apps via sops


