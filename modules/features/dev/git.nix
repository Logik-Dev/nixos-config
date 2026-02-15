{ inputs, ... }:
let

  inherit (inputs.self.meta.owner) email gpg;

  flake.modules.homeManager.git = {
    programs.git = {
      enable = true;
      signing.key = gpg;
      signing.signByDefault = true;
      settings.user.email = email;
    };
  };

in
{
  inherit flake;
}
