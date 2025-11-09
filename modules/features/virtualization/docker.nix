{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) username;
in
{
  flake.modules.nixos.hyper = {
    users.users.${username}.extraGroups = [ "docker" ];
    virtualisation.docker.enable = true;
  };
}
