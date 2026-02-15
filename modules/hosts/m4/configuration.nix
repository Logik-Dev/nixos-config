{
  inputs,
  ...
}:
let
  flake.modules.darwin.m4.imports = with inputs.self.modules.darwin; [
    common
    homebrew
    logikdev
    #yubikey
    test
  ];

  test =
    { config, ... }:
    {
      services.telegraf.enable = true;
      services.telegraf.environmentFiles = config.age.secrets.tailscale.path;
    };

in
{
  inherit flake;
}
