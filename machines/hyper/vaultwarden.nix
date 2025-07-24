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

  # postgresql is listening on local unix socket ONLY
  services.postgresql = {
    enable = true;
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
