{ ... }:
let
  mosquittoModule =
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
