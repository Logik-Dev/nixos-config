{
  # Traefik reverse proxy
  services.traefik-proxy.enable = true;

  # Tailscale VPN
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
  };

  # Unifi Controller
  services.unifi.enable = true;
  services.traefik-proxy.services.unifi = {
    port = 8443;
    https = true;
  };
}