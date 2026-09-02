#!/usr/bin/env bash
# Check that /var/lib/media/music is fully imported into azuracast AND linked
# into the playing "default" playlist. Run on the mlab host (bash -s over ssh).
# LC_ALL=C everywhere so sort/comm agree - a locale mismatch makes comm report
# phantom diffs.
set -u
mariadb() { podman exec -i azuracast sh -c 'mariadb -N -B -u azuracast -p"$MYSQL_PASSWORD" azuracast' 2>/dev/null; }

find /var/lib/media/music -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.ogg' \
  -o -iname '*.m4a' -o -iname '*.wav' -o -iname '*.opus' -o -iname '*.aac' \) -printf '%P\n' \
  | LC_ALL=C sort > /tmp/azuracast-disk.txt
echo "SELECT path FROM station_media;" | mariadb | LC_ALL=C sort > /tmp/azuracast-db.txt

echo "files on disk: $(wc -l < /tmp/azuracast-disk.txt), in library: $(wc -l < /tmp/azuracast-db.txt)"
echo "--- on disk, not yet imported:"
comm -23 /tmp/azuracast-disk.txt /tmp/azuracast-db.txt
echo "--- in library, file gone:"
comm -13 /tmp/azuracast-disk.txt /tmp/azuracast-db.txt
echo "--- playlists (default should be enabled with all tracks):"
echo "SELECT sp.name, CONCAT(spi.c, ' tracks, ', IF(sp.is_enabled=1,'enabled','DISABLED'))
FROM station_playlists sp
JOIN (SELECT playlist_id, COUNT(DISTINCT media_id) c FROM station_playlist_media GROUP BY playlist_id) spi
ON spi.playlist_id=sp.id;" | mariadb
missing=$(comm -23 /tmp/azuracast-disk.txt /tmp/azuracast-db.txt | wc -l)
gone=$(comm -13 /tmp/azuracast-disk.txt /tmp/azuracast-db.txt | wc -l)
rm -f /tmp/azuracast-disk.txt /tmp/azuracast-db.txt
[ "$missing" = 0 ] && [ "$gone" = 0 ] || { echo "OUT OF SYNC: $missing not imported, $gone stale"; exit 1; }
echo "IN SYNC"
