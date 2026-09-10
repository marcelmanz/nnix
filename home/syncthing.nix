{...}: {
  services.syncthing = {
    enable = true;
    settings = {
      devices."mlab" = {
        id = "B67CX6B-ZBPN4KI-32R5KDV-MDRLQMJ-ERKJDLU-UXYGWFH-Z4EYMOY-Q5UEYQN";
        # empty = use global discovery to find mlab (it has openDefaultPorts=true)
        addresses = ["dynamic"];
      };
      folders."bandcamp-cookies" = {
        id = "bandcamp-cookies";
        path = "~/Sync/bandcamp-cookies";
        devices = ["mlab"];
        # laptop only sends cookies, don't accept deletes from mlab
        type = "sendonly";
      };
      folders."dj-library" = {
        id = "dj-library";
        path = "~/Music/dj";
        devices = ["mlab"];
        # mlab is the source of truth, don't send deletes back
        type = "receiveonly";
      };
    };
  };
}
