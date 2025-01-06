{ homelab, ... }:
{
  services.victoriametrics = {
    enable = true;
    retentionPeriod = "26w"; # 6 months
  };

  services.nginx.virtualHosts."victoriametrics.${homelab.domain}" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;
    locations."/".proxyPass = "http://localhost:8428";

  };

}
