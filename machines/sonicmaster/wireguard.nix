{ config, domain, ... }:
{

  sops.secrets.wg-key.sopsFile = ./secrets.yaml;
  sops.secrets.wg-psk.sopsFile = ./secrets.yaml;

  networking.wg-quick.interfaces = {
    wg0 = {
      address = [ "10.11.11.2/24" ];
      dns = [ "192.168.11.53" ];
      privateKeyFile = config.sops.secrets.wg-key.path;

      peers = [
        {
          publicKey = "HUlDX1IpNVELgOmxqiq3h5iWCtQxcGFRa38wRGlFzGE=";
          presharedKeyFile = config.sops.secrets.wg-psk.path;
          allowedIPs = [
            "0.0.0.0/0"
          ];
          endpoint = "wireguard.${domain}:51820";
          persistentKeepalive = 25;
        }
      ];
    };
  };
}
