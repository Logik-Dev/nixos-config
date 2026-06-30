{
  flake.modules.nixos.uptimeKuma = {
    services.uptime-kuma = {
      enable = true;
      settings = {
        PORT = "3001";
        HOST = "127.0.0.1";
      };
    };

    traefik.services.uptime = {
      port = 3001;
      enableAuthelia = true;
    };

    notify.services = [ "uptime-kuma" ];
  };
}
