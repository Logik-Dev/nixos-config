{ ... }:
{

  networking.firewall.allowedTCPPorts = [ 8095 ];
  services.music-assistant = {
    enable = true;
    providers = [
      "airplay"
      "builtin"
      "chromecast"
      "dlna"
      "filesystem_local"
      "hass"
      "hass_players"
      "jellyfin"
      "sonos"
      "spotify"
    ];
  };
}
