{
  flake.modules.nixos.mqtt =
    {
      lib,
      config,
      ...
    }:
    {
      networking.firewall.allowedTCPPorts = [ 1883 ];

      age.secrets.mqtt.owner = "zigbee2mqtt";

      services.mosquitto = {
        enable = true;
        listeners = [
          {
            address = "0.0.0.0";
            port = 1883;
            omitPasswordAuth = false;
            settings.allow_anonymous = true; # IoT devices without auth
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

      traefik.services.zigbee.port = 8788;
      services.zigbee2mqtt = {
        enable = true;
        settings = {
          homeassistant = lib.mkForce true;
          permit_join = true; # à désactiver après appairage
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
            network_key = [
              87
              199
              73
              118
              235
              218
              34
              79
              127
              69
              213
              177
              157
              120
              54
              193
            ]; # 57c74976ebda224f7f45d5b19d7836c1
          };
        };
      };

      systemd.services.zigbee2mqtt.preStart = ''
        umask 077
        printf "mqtt_password: %s\n" "$(cat ${config.age.secrets."mqtt".path})" \
          > ${config.services.zigbee2mqtt.dataDir}/secret.yaml
      '';
    };
}
