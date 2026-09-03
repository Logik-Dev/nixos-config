{ ... }:
{
  flake.modules.nixos.n8n =
    { config, pkgs, ... }:
    let
      url = "n8n.${config.networking.hostName}.${config.constants.domain}";
    in
    {
      # Le task runner JS interne (exécution des nodes « Code ») lance `node`
      # en sous-process : absent du PATH durci du service → « spawn node
      # ENOENT ». On l'ajoute pour que les nodes Code JavaScript fonctionnent.
      # (Le runner Python interne exigerait un virtualenv dédié → mode externe
      # uniquement ; JS suffit pour nos usages, on ne l'active pas.)
      systemd.services.n8n.path = [ pkgs.nodejs ];

      services.n8n = {
        enable = true;
        environment = {
          # Écoute locale : seul Traefik y accède (Authelia devant).
          N8N_LISTEN_ADDRESS = "127.0.0.1";
          N8N_PORT = 5678;

          # URL externe : liens de l'éditeur, webhooks et cookies corrects
          # derrière Traefik (terminaison TLS + 1 proxy).
          N8N_HOST = url;
          N8N_PROTOCOL = "https";
          WEBHOOK_URL = "https://${url}/";
          N8N_EDITOR_BASE_URL = "https://${url}/";
          N8N_PROXY_HOPS = 1;
        };
      };

      traefik.services.n8n = {
        port = 5678;
        enableAuthelia = true;
        category = "Automatisation";
        icon = "di:n8n";
      };

      notify.services = [ "n8n" ];

      # Base applicative où les workflows n8n écrivent leurs données de travail
      # (tri mail : table mail_meta, puis pgvector à l'étage 2). DISTINCTE du
      # store interne de n8n (qui reste sur SQLite, cf. plus bas). Connexion en
      # peer via la socket Unix : le service tourne en DynamicUser nommé « n8n »,
      # et pg_hba a `local all all peer` → le rôle « n8n » = l'utilisateur OS,
      # donc aucun mot de passe ni secret agenix. ensureDBOwnership exige que le
      # nom de la base == le nom du rôle.
      services.postgresql = {
        ensureDatabases = [ "n8n" ];
        ensureUsers = [
          {
            name = "n8n";
            ensureDBOwnership = true;
          }
        ];
      };

      # SQLite + clé de chiffrement des credentials vivent dans
      # /var/lib/private/n8n (DynamicUser + StateDirectory : /var/lib/n8n est
      # un symlink, le sauvegarder ne capture rien). n8n recommande SQLite en
      # instance unique ; Postgres = mode queue/scale inutile ici. Service
      # arrêté pendant le backup (manageService défaut) pour une copie SQLite
      # cohérente.
      backups.sources.n8n = {
        paths = [ "/var/lib/private/n8n" ];
      };
    };
}
