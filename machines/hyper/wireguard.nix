{
  pkgs,
  config,
  ...
}:
let
  sopsFile = ../../secrets/wireguard.hyper.yaml;
in

{
  sops.secrets.wg-key.sopsFile = sopsFile;

  sops.secrets.sonicmaster-psk.sopsFile = sopsFile;

  sops.secrets.oneplus-psk.sopsFile = sopsFile;

  sops.secrets.iphone-psk.sopsFile = sopsFile;

  # NAT and firewall managed by nftables in firewall.nix

  networking.wg-quick.interfaces = {
    wg0 = {
      address = [ "10.11.11.1/24" ];
      listenPort = 51820;
      privateKeyFile = config.sops.secrets.wg-key.path;

      # postUp and preDown removed - managed by nftables

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

        {
          # Iphone
          publicKey = "AS81dlMYnuKpF4y0A2rN5gC5qcood5tumSDIgjhSiAQ=";
          presharedKeyFile = config.sops.secrets.iphone-psk.path;
          allowedIPs = [
            "10.11.11.4/32"
          ];
        }
      ];
    };

  };
}
