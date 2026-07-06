{ ... }:
let
  zigbee2mqttModule =
    {
      config,
      lib,
      ...
    }:
    {
      age.secrets."zigbee2mqtt-network-key".owner = "zigbee2mqtt";

      traefik.services.zigbee = {
        port = 8788;
        enableAuthelia = true;
        category = "Maison";
        icon = "di:zigbee2mqtt";
        title = "Zigbee2MQTT";
      };

      services.zigbee2mqtt = {
        enable = true;
        settings = {
          homeassistant = lib.mkForce true;
          permit_join = false; # ré-activer via l'UI z2m uniquement pour appairer
          serial.port = "/dev/ttyUSB0";
          mqtt = {
            server = "mqtt://localhost:1883";
            user = "zigbee2mqtt";
            password = "!secret mqtt_password";
          };
          frontend = {
            enabled = true;
            port = 8788;
            host = "0.0.0.0";
          };
          # Valeurs fixées sur le réseau déjà gravé dans le coordinateur.
          # "GENERATE" est incompatible avec ce module : le configuration.yaml
          # est recopié depuis le store à chaque démarrage, donc un nouveau
          # réseau aléatoire serait généré à chaque redémarrage et ne
          # correspondrait plus au stick (-> "configuration-adapter mismatch").
          advanced = {
            pan_id = 668; # 0x29c
            ext_pan_id = [
              122
              141
              176
              91
              162
              163
              82
              215
            ]; # 7a8db05ba2a352d7
            # Rotated 2026-07-02: the old key was committed in plaintext to this
            # PUBLIC repo. New key lives in agenix (zigbee2mqtt-network-key) and
            # is injected into secret.yaml by the preStart below. Changing it
            # re-forms the Zigbee network → all devices must be re-paired.
            network_key = "!secret network_key";
          };
        };
      };

      systemd.services.zigbee2mqtt.preStart = ''
        umask 077
        {
          printf "mqtt_password: %s\n" "$(cat ${config.age.secrets."mqtt".path})"
          printf "network_key: %s\n" "$(cat ${config.age.secrets."zigbee2mqtt-network-key".path})"
        } > ${config.services.zigbee2mqtt.dataDir}/secret.yaml
      '';

      # database.db (device state) + coordinator_backup.json — the Zigbee
      # network pairings. Stopped during backup for a consistent snapshot.
      backups.sources.zigbee2mqtt = {
        paths = [ config.services.zigbee2mqtt.dataDir ];
        extraRepositories.local = "/mnt/local";
      };
    };
in
{
  flake.modules.nixos.mqtt.imports = [ zigbee2mqttModule ];
}
