{
  config,
  pkgs,
  username,
  lib,
  ...
}:
{

  # signing key
  sops.secrets.cache-private-key.sopsFile = ../../secrets/hyper.yaml;

  services.nix-serve = {
    enable = true;
    openFirewall = true;
    secretKeyFile = "${config.sops.secrets.cache-private-key.path}";
  };

}
