{
  config,
  username,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    pgloader
    sqlite
  ];

  sops.secrets."vaultwarden.env" = {
    owner = "vaultwarden";
    format = "dotenv";
    key = "";
    sopsFile = ../../secrets/vaultwarden.hyper.env;
    restartUnits = [ "vaultwarden.service" ];
  };

  services.vaultwarden = {
    enable = true;
    environmentFile = config.sops.secrets."vaultwarden.env".path;
    dbBackend = "postgresql";
  };

  # traefik
  services.traefik-proxy.services.vaultwarden.port = 8222;

  # postgresql listening on TCP for cluster access
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    package = pkgs.postgresql_15;
    ensureUsers = [
      {
        name = "vaultwarden";
        ensureDBOwnership = true;
      }
    ];
    ensureDatabases = [ "vaultwarden" ];
    identMap = ''
      localusersmap root        postgres
      localusersmap postgres    postgres
      localusersmap ${username} postgres
      localusersmap /^(.*)$     \1
    '';
    authentication = lib.mkOverride 10 ''
      local sameuser  all     peer            map=localusersmap
      host  vaultwarden vaultwarden 192.168.0.0/16  md5
      host  all        postgres    192.168.0.0/16  md5
    '';

  };

  # backups
  services.backups.configurations.vaultwarden = {
    source_directories = [ "/var/lib/vaultwarden/attachments" ];
    postgresql_databases = [
      {
        name = "vaultwarden";
        username = "vaultwarden";
      }
    ];
  };

}
