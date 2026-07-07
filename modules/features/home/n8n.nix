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

      # SQLite + clé de chiffrement des credentials vivent dans /var/lib/n8n
      # (n8n recommande SQLite en instance unique ; Postgres = mode queue/scale
      # inutile ici). Service arrêté pendant le backup (manageService défaut)
      # pour une copie SQLite cohérente.
      backups.sources.n8n = {
        paths = [ "/var/lib/n8n" ];
      };
    };
}
