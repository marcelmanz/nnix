{
  config,
  pkgs,
  ...
}: let
  domain = "matrix.marcel.cool";

  cinnyConfig = pkgs.writeText "cinny-config.json" ''
    {
      "defaultHomeserver": 0,
      "homeserverList": [
        "${domain}"
      ],
      "allowCustomHomeservers": true
    }
  '';
in {
  services.nginx.virtualHosts.${domain} = {
    locations."/" = {
      root = pkgs.cinny-unwrapped;
      index = "index.html";
      extraConfig = "try_files $uri $uri/ /index.html =404;";
    };

    locations."/config.json" = {
      extraConfig = ''
        add_header Content-Type application/json;
        add_header Access-Control-Allow-Origin *;
        return 200 '${builtins.readFile cinnyConfig}';
      '';
    };
  };
}
