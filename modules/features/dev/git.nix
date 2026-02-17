{
  flake.modules.homeManager.git =
    { config, ... }:
    {
      programs.git = {
        enable = true;
        signing.key = config.constants.users.logikdev.gpg;
        signing.signByDefault = true;
        settings.user.email = config.constants.users.logikdev.email;
      };
    };
}
