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

    # DynamicUser service: real state lives under /var/lib/private. Stop it
    # during backup (default) so the SQLite monitor DB is consistent.
    backups.sources.uptime-kuma = {
      paths = [ "/var/lib/private/uptime-kuma" ];
      extraRepositories.local = "/mnt/local";
    };
  };
}
