{ inputs, ... }:
let

  inherit (inputs.self.meta.owner) fullname email gpg;

  flake.modules.homeManager.dev = {
    programs.git = {
      enable = true;
      signing.key = gpg;
      signing.signByDefault = true;
      settings.user.email = email;
    };

    programs.jujutsu = {
      enable = true;
      settings = {
        user = {
          inherit email;
          name = fullname;
        };
        inherit email;
        signing.behavior = "own";
        signing.backend = "gpg";
        signing.key = gpg;
      };
    };
  };
in
{
  inherit flake;
}
