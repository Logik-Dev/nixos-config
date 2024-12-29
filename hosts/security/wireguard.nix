{
  pkgs,
  config,
  ...
}:

{
  sops.secrets.wg-key = {
    sopsFile = ./secrets.yaml;
  };

  sops.secrets.sonicmaster-psk = {
    sopsFile = ./secrets.yaml;
  };

  sops.secrets.oneplus-psk = {
    sopsFile = ./secrets.yaml;
  };

  networking.nat = {
    enable = true;
    #enableIPv6 = true;
    externalInterface = "enp5s0";
    internalInterfaces = [ "wg0" ];
  };

  networking.firewall.allowedUDPPorts = [ 51820 ];

  networking.wg-quick.interfaces = {
    wg0 = {
      address = [ "10.11.11.1/24" ];
      listenPort = 51820;
      privateKeyFile = config.sops.secrets.wg-key.path;

      postUp = ''
        ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.11.11.1/24 -o enp5s0 -j MASQUERADE
      '';

      preDown = ''
        ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.11.11.1/24 -o enp5s0 -j MASQUERADE
      '';

      peers = [
        {
          # Sonicmaster
          publicKey = "RmC9rz6n7B6Oh8JngbWFbfgwWzzd969XUCRC4N/x5GM=";
          presharedKeyFile = config.sops.secrets.sonicmaster-psk.path;
          allowedIPs = [
            "10.11.11.2/32"
          ];
        }

        {
          # Oneplus
          publicKey = "8h5hx3v5VV1nSVd/0HKFveCzq4NYYcEgFiH8Q/8wMgc=";
          presharedKeyFile = config.sops.secrets.oneplus-psk.path;
          allowedIPs = [
            "10.11.11.3/32"
          ];
        }
      ];
    };

  };
}
