{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) domain email;

  flake.modules.homeManager.passwords.imports = [
    passwordStore
    vaultwardenClient
  ];

  passwordStore = {
    programs.password-store = {
      enable = true;
      settings.PASSWORD_STORE_DIR = "$HOME/.password-store";
    };
  };

  vaultwardenClient =
    { pkgs, ... }:
    {
      programs.rbw = {
        enable = true;
        settings.base_url = "https://vaultwarden.k8sp.home.${domain}";
        settings.email = email;
        settings.pinentry = pkgs.pinentry-gnome3;
      };
    };

in
{
  inherit flake;
}
