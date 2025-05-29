{ ... }:
{
  imports = [
    ./borgmatic.nix
    ../common
    ../../modules/nginx
    ./vaultwarden.nix
    ./wireguard.nix
  ];
}
