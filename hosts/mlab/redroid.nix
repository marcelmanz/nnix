{
  config,
  pkgs,
  lib,
  ...
}: {
  boot.kernelModules = ["binder_linux"];
  systemd.tmpfiles.rules = [
    "d /var/lib/redroid 0755 root root -"
  ];
  virtualisation.oci-containers.containers.redroid = {
    image = "redroid/redroid:11.0.0-latest";
    autoStart = true;
    privileged = true;
    ports = [
      "127.0.0.1:5555:5555" # adb port for scrcpy connections
    ];
    volumes = [
      "/var/lib/redroid:/data"
    ];
    cmd = [
      "androidboot.redroid_width=1080"
      "androidboot.redroid_height=1920"
      "androidboot.redroid_dpi=420"
      "androidboot.redroid_fps=30"
      # Starts vendor.uinputd at boot -> creates the virtual touch device before
      # EventHub scans /dev/input. Without it /dev/input is empty and every
      # injected tap (scrcpy --mouse=sdk, adb input tap) is silently dropped.
      "androidboot.use_redroid_stream=1"
      # redroid lets any ro.* prop be overridden as a bare boot arg (redroid-doc README).
      # Spoofs a certified stock device so WhatsApp drops its "Custom ROM" warning.
      "ro.build.type=user"
      "ro.build.tags=release-keys"
      "ro.boot.verifiedbootstate=green"
      "ro.boot.flash.locked=1"
      "ro.boot.veritymode=enforcing"
      "ro.product.model=Pixel"
      "ro.product.brand=google"
      "ro.product.manufacturer=Google"
    ];
  };
}
