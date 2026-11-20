{pkgs, ...}: let
  djStick = pkgs.writeShellApplication {
    name = "dj-stick";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gnused
      jq
      libnotify
      openssh
      rsync
      udisks
      util-linux
    ];
    text = ''
      usage="usage: dj-stick [--yes] <partition, e.g. sdb1>"
      ask=1
      if [ "''${1:-}" = "--yes" ]; then
        ask=0
        shift
      fi
      partition="''${1:?$usage}"
      device="/dev/''${partition#/dev/}"
      library="''${DJ_LIBRARY:-$HOME/Music/dj}"
      rekordbox="''${DJ_REKORDBOX:-$HOME/Music/dj-rekordbox}"
      syncthingConfig="''${XDG_STATE_HOME:-$HOME/.local/state}/syncthing/config.xml"
      notifyId=0

      show() {
        local urgency=$1 title=$2 body=$3
        shift 3
        notifyId=$(notify-send --app-name="DJ stick" --icon=drive-removable-media \
          --urgency="$urgency" --print-id --replace-id="$notifyId" "$@" "$title" "$body")
      }

      fail() {
        show critical "Stick not updated" "$1" --expire-time=0
        exit 1
      }

      reportProgress() {
        local line percent rate eta lastUpdate=0
        while IFS= read -r -d $'\r' line || [ -n "$line" ]; do
          read -r _ percent rate eta _ <<<"$line" || true
          percent=''${percent%\%}
          [[ $percent =~ ^[0-9]+$ ]] || continue
          if ((SECONDS - lastUpdate >= 2)); then
            lastUpdate=$SECONDS
            show normal "Copying DJ library" "$percent % at $rate, $eta left" \
              --expire-time=0 --hint="int:value:$percent"
          fi
        done
      }

      [ -b "$device" ] || fail "$device is not a block device."

      if [ "$ask" = 1 ]; then
        choice=$(notify-send --app-name="DJ stick" --icon=drive-removable-media \
          --expire-time=0 --wait \
          --action=copy="Replace with DJ library" --action=skip="Leave it" \
          "FIESTA stick connected" \
          "Replace /dj and /PIONEER on the stick with the DJ library? Everything else stays." || true)
        [ "$choice" = copy ] || exit 0
      fi

      [ -f "$rekordbox/rekordbox/exportLibrary.db" ] ||
        fail "There is no Rekordbox export in $rekordbox yet."

      exportState=$(ssh -o BatchMode=yes -o ConnectTimeout=5 mlab \
        systemctl is-active dj-rekordbox.service 2>/dev/null || true)
      case "$exportState" in
        active | activating | reloading | deactivating)
          fail "An export is running on mlab. Try again when djexport.marcel.cool says Ready to copy."
          ;;
      esac

      apiKey=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$syncthingConfig")
      for folder in dj-library dj-rekordbox; do
        folderStatus=$(curl -fsS -H "X-API-Key: $apiKey" \
          "http://127.0.0.1:8384/rest/db/status?folder=$folder") ||
          fail "Can't get the $folder folder from Syncthing on this laptop."
        folderState=$(jq -r .state <<<"$folderStatus")
        itemsLeft=$(jq -r .needTotalItems <<<"$folderStatus")
        if [ "$folderState" != idle ] || [ "$itemsLeft" != 0 ]; then
          fail "Syncthing is still receiving $folder ($itemsLeft items left). Try again when djexport.marcel.cool says Ready to copy."
        fi
      done

      mountPoint=$(findmnt -nro TARGET --source "$device" | head -n1 || true)
      if [ -z "$mountPoint" ]; then
        udisksctl mount --block-device "$device" --no-user-interaction >/dev/null ||
          fail "Could not mount $device."
        mountPoint=$(findmnt -nro TARGET --source "$device" | head -n1 || true)
      fi
      [ -n "$mountPoint" ] || fail "Could not find where $device is mounted."
      fsType=$(findmnt -nro FSTYPE --source "$device" | head -n1 || true)
      [ "$fsType" = vfat ] || fail "The stick is $fsType, CDJs need FAT32."

      needed=$(du -scb --exclude=.stfolder --exclude=.stversions "$library" "$rekordbox" |
        tail -n1 | cut -f1)
      replaced=$(du -scb "$mountPoint/dj" "$mountPoint/PIONEER" 2>/dev/null | tail -n1 | cut -f1 || true)
      available=$(($(df --output=avail -B1 "$mountPoint" | tail -n1 | tr -d ' ') + ''${replaced:-0}))
      if ((needed + 64 * 1024 * 1024 > available)); then
        fail "The library needs $(numfmt --to=iec "$needed"), the stick has $(numfmt --to=iec "$available") for it."
      fi

      staging=$(mktemp -d)
      ln -s "$library" "$staging/dj"
      ln -s "$rekordbox" "$staging/PIONEER"

      trap 'fail "The copy stopped before it finished. Plug the stick in again to retry."' TERM INT

      show normal "Copying DJ library" "Starting" --expire-time=0 --hint=int:value:0
      errors=$(mktemp)
      if rsync -rtL --modify-window=2 --delete-before --info=progress2 --no-inc-recursive \
        --filter='P /*' --exclude=.stfolder --exclude=.stversions \
        "$staging/" "$mountPoint/" 2>"$errors" | reportProgress; then
        rsyncStatus=0
      else
        rsyncStatus=''${PIPESTATUS[0]}
      fi
      if [ "$rsyncStatus" != 0 ]; then
        fail "rsync failed ($rsyncStatus): $(tail -n3 "$errors")"
      fi

      show normal "Copying DJ library" "Writing the last data to the stick" \
        --expire-time=0 --hint=int:value:100
      sync -f "$mountPoint"
      udisksctl unmount --block-device "$device" --no-user-interaction >/dev/null ||
        fail "Copied, but could not unmount $device. Eject it before unplugging."
      disk=$(lsblk -no PKNAME "$device" | head -n1)
      if [ -n "$disk" ]; then
        udisksctl power-off --block-device "/dev/$disk" --no-user-interaction >/dev/null 2>&1 || true
      fi
      trap - TERM INT
      show normal "Stick ready" \
        "Copied $(numfmt --to=iec "$needed") to /dj and /PIONEER. Safe to unplug." --expire-time=0
    '';
  };
in {
  home.packages = [djStick];

  systemd.user.services."dj-stick@" = {
    Unit = {
      Description = "Offer to copy the DJ library to the CDJ stick on %I";
      BindsTo = ["dev-%i.device"];
      After = ["dev-%i.device" "graphical-session.target"];
    };
    Service = {
      Type = "exec";
      ExecStart = "${djStick}/bin/dj-stick %I";
    };
  };
}
