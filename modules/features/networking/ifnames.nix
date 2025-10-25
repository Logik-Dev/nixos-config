let
  flake.modules.nixos = { inherit hyper; };

  hyper = {
    systemd.network.links."10-management" = {
      matchConfig.MACAddress = "fc:34:97:10:ca:04";
      linkConfig.Name = "management";
    };
    systemd.network.links."10-vms" = {
      matchConfig.MACAddress = "98:b7:85:00:8f:f2";
      linkConfig.Name = "vms";
    };
  };
in
{
  inherit flake;
}
