{
  flake.modules.nixos.hyper =
    { config, ... }:
    {
      users.users.${config.constants.users.logikdev.username}.extraGroups = [ "docker" ];
      virtualisation.docker.enable = true;
    };
}
