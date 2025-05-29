{
  pkgs,
  username,
  ...
}:
{
  networking.firewall.allowedTCPPorts = [ 8443 ];
  networking.nftables.enable = true;
  networking.useNetworkd = true;

  virtualisation.libvirtd.enable = true;
  virtualisation.incus = {
    enable = true;
    package = pkgs.incus;
    preseed = {
      config = {
        "core.https_address" = ":8443";
        "core.metrics_address" = ":8444";
        "core.metrics_authentication" = false;
      };
    };
  };

  users.users.${username}.extraGroups = [
    "libvirtd"
    "incus-admin"
  ];

}
