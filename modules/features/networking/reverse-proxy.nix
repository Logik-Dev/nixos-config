{ inputs, ... }:
{
  flake.modules.nixos.reverse-proxy = {
    imports = [ inputs.self.modules.nixos.nginx ];
    services.reverse-proxy.enable = true;
  };
}
