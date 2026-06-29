let

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
    { pkgs, config, ... }:
    {
      programs.rbw = {
        enable = true;
        settings.base_url = "https://vaultwarden.hyper.${config.constants.domain}";
        settings.email = config.constants.users.logikdev.email;
        settings.pinentry = pkgs.pinentry-gnome3;
      };
    };

in
{
  inherit flake;
}
