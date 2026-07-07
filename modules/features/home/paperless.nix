{ ... }:
{
  flake.modules.nixos.paperless =
    { config, ... }:
    {
      age.secrets."paperless-admin-pw".owner = "paperless";

      traefik.services.paperless = {
        port = 28981;
        enableAuthelia = true;
        category = "Maison";
        icon = "di:paperless-ngx";
      };

      services.paperless = {
        enable = true;
        # Documents + index + miniatures sur /mnt/local (partition de données
        # dédiée, root:root, 394 Go libres). PAS /mnt/ultra : ce mount
        # appartient à logikdev, or systemd-tmpfiles refuse de créer les
        # sous-dossiers (consume/media) via une « unsafe path transition »
        # quand un parent appartient à un utilisateur non-root. Les
        # métadonnées vivent dans postgres (couvert par pg-dumpall + PITR).
        dataDir = "/mnt/local/paperless";
        address = "127.0.0.1";
        port = 28981;
        database.createLocally = true;
        passwordFile = config.age.secrets."paperless-admin-pw".path;
        # Tika + Gotenberg locaux : OCR des .docx/.odt et import d'e-mails.
        configureTika = true;
        # Laisse logikdev déposer des scans dans le dossier consume.
        consumptionDirIsPublic = true;
        settings = {
          PAPERLESS_OCR_LANGUAGE = "fra+eng";
          PAPERLESS_TIME_ZONE = "Europe/Paris";
          # URL externe pour que Django fasse confiance à l'origine proxifiée
          # par Traefik (CSRF).
          PAPERLESS_URL = "https://paperless.${config.networking.hostName}.${config.constants.domain}";

          # SSO via le header Remote-User d'Authelia (forwardAuth). Sûr
          # UNIQUEMENT parce que Traefik strippe tout Remote-* entrant avant
          # le forwardAuth (middleware stripAuthHeaders) : sans ça, le bypass
          # LAN/Tailscale d'Authelia laisserait n'importe qui forger le header.
          # L'API reste sur l'auth par token (apps mobiles) — on n'active pas
          # PAPERLESS_ENABLE_HTTP_REMOTE_USER_API.
          PAPERLESS_ENABLE_HTTP_REMOTE_USER = true;
          PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME = "HTTP_REMOTE_USER";
          # Le logout Paperless renvoie vers le logout Authelia (session SSO).
          PAPERLESS_LOGOUT_REDIRECT_URL = "https://auth.${config.networking.hostName}.${config.constants.domain}/logout";
        };
      };

      notify.services = [
        "paperless-web"
        "paperless-consumer"
        "paperless-scheduler"
        "paperless-task-queue"
        "tika"
        "gotenberg"
      ];

      # Les originaux sont immuables une fois consommés → pas besoin d'arrêter
      # le service. Les métadonnées postgres sont capturées par le pg-dumpall +
      # PITR pgBackRest du cluster, pas ici.
      backups.sources.paperless = {
        paths = [ "/mnt/local/paperless" ];
        manageService = false;
      };

      # Dossier Syncthing d'ingestion : Mac (~/Paperless) → ce consume dir.
      # Paperless avale puis supprime, et la suppression est propagée → l'inbox
      # se vide au fil du classement. Déclaratif via overrideFolders = true
      # (voir storage/syncthing.nix) ; fusionne avec les autres folders déclarés.
      services.syncthing.settings.folders."paperless-consume" = {
        path = "/mnt/local/paperless/consume";
        label = "Paperless Consume";
        devices = [
          "hyper"
          "m4"
        ];
        ignorePerms = true;
      };
    };
}
