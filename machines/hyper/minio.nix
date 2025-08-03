{ config, ... }:
{

  sops.secrets.minio = {
    sopsFile = ../../secrets/minio.hyper.env;
    format = "dotenv";
    key = "";
  };

  services.minio = {
    enable = true;
    rootCredentialsFile = config.sops.secrets.minio.path;
    dataDir = [ "/mnt/storage/minio" ];
  };
}
