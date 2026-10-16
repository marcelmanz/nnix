{services, ...}: {
  services.vikunja = {
    enable = true;
    frontendScheme = "https";
    frontendHostname = "todo.marcel.cool";
    address = "127.0.0.1";
    port = services.vikunja.port;
    settings.service.enableregistration = false;
  };
}
