{config, ...}: {
  programs.ssh.knownHosts."eu.nixbuild.net".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIElijTSFa+a3l0oMnGMSPQQsFJp/MYdtTBEeheQjJ0vY";

  nix = {
    distributedBuilds = true;
    settings.builders-use-substitutes = true;
    buildMachines = [
      {
        hostName = "eu.nixbuild.net";
        systems = ["x86_64-linux" "aarch64-linux"];
        maxJobs = 100;
        supportedFeatures = ["benchmark" "big-parallel"];
        sshKey = "/home/marcel/.ssh/my-nixbuild-key";
      }
    ];
  };
}
