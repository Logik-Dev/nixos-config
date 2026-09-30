_:
let
  mosquittoModule =
    {
      config,
      ...
    }:
    {
      # **Loopback uniquement depuis le 2026-09-30.** Plus aucun port ouvert :
      # les trois clients — zigbee2mqtt, rankoder et Home Assistant natif —
      # vivent tous sur cet hôte. La VM HAOS était le seul client distant, et
      # elle est arrêtée.
      #
      # Ça referme l'essentiel de SEC-3b sans en traiter la lettre : le trafic
      # ne quitte plus la machine, donc l'absence de TLS et le mot de passe
      # partagé ne sont plus exposés à un segment non fiable. Restent les
      # comptes distincts et les ACL minimales, qui gardent leur valeur contre
      # un service local compromis mais ne sont plus urgents.
      #
      # Vérifié avant de fermer : 3 connexions établies, toutes depuis
      # 127.0.0.1, et la règle `br-iot` n'avait compté aucun paquet depuis
      # l'arrêt de la VM.

      age.secrets.mqtt.owner = "zigbee2mqtt";

      notify.services = [ "mosquitto" ];

      # mosquitto.db holds the retained messages (working directory).
      backups.sources.mosquitto = {
        paths = [ "/var/lib/mosquitto" ];
      };

      services.mosquitto = {
        enable = true;
        listeners = [
          # Single listener, authentication required (no anonymous), **lié au
          # loopback**. Les trois clients y sont : zigbee2mqtt, rankoder et HA
          # natif. Le bind restreint double la fermeture du pare-feu — si une
          # règle disparaissait, le courtier resterait injoignable du réseau.
          #
          # `0.0.0.0` jusqu'au 2026-09-30, pour la VM HAOS qui était le seul
          # client distant. Si un objet devait un jour publier en direct, ce
          # bind est le premier endroit à rouvrir — et il faudrait alors
          # reprendre SEC-3b pour de bon (comptes distincts, ACL, TLS 8883).
          {
            address = "127.0.0.1";
            port = 1883;
            omitPasswordAuth = false;
            settings.allow_anonymous = false;
            users.zigbee2mqtt = {
              passwordFile = config.age.secrets."mqtt".path;
              acl = [ "readwrite zigbee2mqtt/#" ];
            };
            users.homeassistant = {
              passwordFile = config.age.secrets."mqtt".path;
              acl = [ "readwrite #" ];
            };
          }
        ];
      };
    };
in
{
  flake.modules.nixos.mqtt.imports = [ mosquittoModule ];
}
