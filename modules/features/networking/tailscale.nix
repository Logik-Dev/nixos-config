{
  flake.modules.homeManager.desktop = {
    services.tailscale-systray.enable = true;
  };

  flake.modules.nixos.common =
    { config, hostSecret, ... }:
    {
      age.secrets.tailscale.rekeyFile = hostSecret "tailscale";
      services.tailscale = {
        enable = true;
        authKeyFile = config.age.secrets.tailscale.path;
      };
    };

  flake.modules.nixos.hyper = {
    services.tailscale.useRoutingFeatures = "both";
  };
}
