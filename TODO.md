- [ ] Setup Anki Server in mlab
- [ ] Fix Soulbeet
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

- [x] Setup a radio

- [x] Setup an auto sync of bandcamp buys

- [x] Setup SOPS properly
  - [x] Setup passwords for vps apps via sops


