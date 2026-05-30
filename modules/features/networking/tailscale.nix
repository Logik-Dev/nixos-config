{

  flake.modules.darwin.tailscale = {
    # Must be set to configure DNS
    networking.knownNetworkServices = [
      "Thunderbolt Bridge"
      "Wi-Fi"
    ];
    services.tailscale = {
      enable = true;
      overrideLocalDns = true;
    };
  };

  flake.modules.nixos.tailscale =
    { config, ... }:
    {
      services.tailscale = {
        enable = true;
        authKeyFile = config.age.secrets.tailscale.path;
      };
    };

}
