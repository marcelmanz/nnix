{pkgs, ...}: let
  batteryGuard = pkgs.writeShellScript "battery-guard" ''
    export PATH=${pkgs.lib.makeBinPath [pkgs.coreutils pkgs.yad pkgs.systemd]}

    promptBelowPercent=10
    repromptStepPercent=3
    pollSeconds=15
    promptTimeoutSeconds=60

    battery=$(echo /sys/class/power_supply/BAT* | cut -d' ' -f1)
    [ -d "$battery" ] || exit 0

    lastPromptedPercent=""

    while true; do
      status=$(cat "$battery/status")
      capacity=$(cat "$battery/capacity")

      if [ "$status" != "Discharging" ]; then
        lastPromptedPercent=""
      elif [ "$capacity" -le "$promptBelowPercent" ] &&
        { [ -z "$lastPromptedPercent" ] || [ "$capacity" -le $((lastPromptedPercent - repromptStepPercent)) ]; }; then
        lastPromptedPercent=$capacity
        yad --name=battery-guard --class=battery-guard \
          --title="Battery low" --center --on-top --sticky --fixed \
          --width=420 --image=battery-caution \
          --text="<big><b>Battery at ''${capacity}%</b></big>\n\nThe system will sleep in 1 minute to keep your session." \
          --timeout=$promptTimeoutSeconds --timeout-indicator=bottom \
          --button="Keep working:1" --button="Sleep now:0"
        case $? in
          1 | 252) ;;
          *)
            lastPromptedPercent=""
            systemctl suspend
            ;;
        esac
      fi

      sleep $pollSeconds
    done
  '';
in {
  systemd.user.services.battery-guard = {
    Unit = {
      Description = "Warn on low battery and suspend if unanswered";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };

    Service = {
      ExecStart = "${batteryGuard}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
