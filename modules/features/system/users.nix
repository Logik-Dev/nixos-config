{
  inputs,
  lib,
  ...
}:
{
  flake.modules = lib.mkMerge [
    (inputs.self.factory.user "logikdev" true)
    {
      # TODO move to the right place
      nixos.hyper = {
        users.groups.media.gid = 991;
      };
    }
  ];
}
