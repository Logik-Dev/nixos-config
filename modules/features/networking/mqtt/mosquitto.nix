{ ... }:
let
  mosquittoModule =
    {
      config,
      lib,
      ...
    }:
    {
      # MQTT is not encrypted (yet) and shared credentials are used, so keep it
      # off every untrusted interface: only the IoT bridge (where the Home
      # Assistant VM lives) is opened. loopback is always allowed and carries
      # zigbee2mqtt/rankoder; LAN, Tailscale and the management NIC stay closed.
      networking.firewall.interfaces."br-iot".allowedTCPPorts = [ 1883 ];

      age.secrets.mqtt.owner = "zigbee2mqtt";

      notify.services = [ "mosquitto" ];

      # mosquitto.db holds the retained messages (working directory).
      backups.sources.mosquitto = {
        paths = [ "/var/lib/mosquitto" ];
      };

      services.mosquitto = {
        enable = true;
        listeners = [
          # Single listener, authentication required (no anonymous). z2m connects
          # over loopback and Home Assistant (192.168.21.181) over the LAN, both
          # with the credentials below. Closing anonymous is the whole point:
          # previously anyone on the LAN/Tailscale could read and publish.
          {
            address = "0.0.0.0";
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
