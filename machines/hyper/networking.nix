{
  hostname,
  ...
}:
{
  # Networking and hostname
  networking.hostName = hostname;

  # Persistent network interface names
  systemd.network.links."10-management" = {
    matchConfig.MACAddress = "fc:34:97:10:ca:04";
    linkConfig.Name = "management";
  };
  systemd.network.links."10-vms" = {
    matchConfig.MACAddress = "98:b7:85:00:8f:f2";
    linkConfig.Name = "vms";
  };
}
