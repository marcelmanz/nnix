{pkgs}:
pkgs.buildGoModule rec {
  pname = "wikipedia-cli";
  version = "0.4.1";
  src = pkgs.fetchFromGitHub {
    owner = "tamnd";
    repo = "wikipedia-cli";
    rev = "v${version}";
    sha256 = "sha256-DWG9nH+5gJf4BUa9RRCzcfSdT6bkEBvF/t38L1BuKZU=";
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
