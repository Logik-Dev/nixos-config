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
    sopsFile = ../../secrets/vaultwarden.security.env;
    restartUnits = [ "vaultwarden.service" ];
  };

  services.vaultwarden = {
    enable = true;
    environmentFile = config.sops.secrets."vaultwarden.env".path;
    dbBackend = "postgresql";
  };

  # vaultwarden port
  networking.firewall.allowedTCPPorts = [ 8222 ];

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

}
