{
  pkgs,
  services,
  ...
}: {
  services.vikunja = {
    enable = true;
    package = pkgs.vikunja-git;
    frontendScheme = "https";
    frontendHostname = "todo.marcel.cool";
    address = "127.0.0.1";
    port = services.vikunja.port;
    settings.service.enableregistration = false;
  };
}
