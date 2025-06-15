{
  config,
  username,
  domain,
  hosts,
  ...
}:
{

  # photos volume mounted by incus
  systemd.tmpfiles.settings = {
    "10-paperless-documents" = {
      "/mnt/photos/documents" = {
        d = {
          group = "media";
          mode = "750";
          user = config.services.paperless.user;
        };
      };
    };
  };

  sops.secrets.paperless = {
    sopsFile = ../../secrets/medias.yaml;
    owner = config.services.paperless.user;
  };

  sops.secrets."paperless.env" = {
    sopsFile = ../../secrets/paperless.medias.env;
    format = "dotenv";
    key = "";
    owner = config.services.paperless.user;
  };

  users.users.paperless.extraGroups = [ "media" ];

  services.paperless = {
    enable = true;
    passwordFile = config.sops.secrets.paperless.path;
    mediaDir = "/mnt/photos/documents";
    database.createLocally = true;
    configureTika = true;
    address = "0.0.0.0";
    environmentFile = config.sops.secrets."paperless.env".path;
    settings = {
      PAPERLESS_ADMIN_USER = username;
      PAPERLESS_OCR_LANGUAGE = "fra+eng";
      PAPERLESS_URL = "https://papers.${domain}";
      PAPERLESS_TRUSTED_PROXIES = hosts.proxy.ipv4;
      PAPERLESS_TIMEZONE = "Europe/Paris";
    };
  };

  networking.firewall.allowedTCPPorts = [ 28981 ];

}
