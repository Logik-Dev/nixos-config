{
  flake.modules.homeManager.git =
    { config, pkgs, ... }:
    let
      key =
        if pkgs.stdenv.isDarwin then
          config.constants.users.logikdev.sshKeyMac
        else
          config.constants.users.logikdev.sshKey;
    in
    {
      programs.git = {
        enable = true;
        signing.key = key;
        signing.signByDefault = true;
        settings.user = {
          name = config.constants.users.logikdev.fullname;
          email = config.constants.users.logikdev.email;
        };
        settings.gpg.format = "ssh";
      };
    };
}
