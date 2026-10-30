{pkgs}:
pkgs.buildGoModule rec {
  pname = "wikipedia-cli";
  version = "0.4.1";
  src = pkgs.fetchFromGitHub {
    owner = "marcelmanz";
    repo = "wikipedia-cli";
    rev = "67453898e6ebbc45d4130858fb3a833f290920c7";
    sha256 = "sha256-3AcZaBbbEdmY69XnZqQ9k/sHsFK9VgCXQs/BACvjw7o=";
  };
  vendorHash = "sha256-cwgtG5vTd8W4nOntvOEHFCV7eJQMcO3oEL4nN3YnO60=";
  subPackages = ["cmd/wiki"];
  ldflags = [
    "-s"
    "-w"
    "-X github.com/tamnd/wikipedia-cli/cli.Version=v${version}"
  ];
  doCheck = false;
}
