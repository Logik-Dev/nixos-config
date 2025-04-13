{
  homelab,
  pkgs,
  config,
  ...
}:
{

  imports = [
    ./lovelace.nix
    ./music-assistant.nix
  ];

  sops.secrets."home-assistant-secrets.yaml" = {
    sopsFile = ./secrets.yaml;
    format = "yaml";
    key = "";
    restartUnits = [ "home-assistant.service" ];
    owner = "hass";
    path = "/var/lib/hass/secrets.yaml";
  };

  # needed for sonos
  networking.firewall.allowedTCPPorts = [ 1400 ];

  services.nginx.virtualHosts."home.${homelab.domain}" = {
    enableACME = true;
    acmeRoot = null;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://[::1]:8123";
      proxyWebsockets = true;
    };
  };

  # create automations.yaml
  systemd.tmpfiles.rules = [
    "f ${config.services.home-assistant.configDir}/automations.yaml 0755 hass hass"
  ];

  services.home-assistant = {
    enable = true;
    lovelaceConfigWritable = true;
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      universal-remote-card
    ];
    extraPackages =
      python3Packages: with python3Packages; [
        androidtvremote2
        gtts
        python-kasa
      ];
    extraComponents = [
      "alexa"
      "androidtv"
      "esphome"
      "fire_tv"
      "jellyfin"
      "lifx"
      "met"
      "music_assistant"
      "radarr"
      "radio_browser"
      "sonarr"
      "sonos"
      "tplink_tapo"
    ];
    config = {
      http = {
        server_host = "::1";
        trusted_proxies = [ "::1" ];
        use_x_forwarded_for = true;
      };
      default_config = { };

      sonos = {
        media_player = {
          hosts = [ "192.168.21.185" ];
        };
      };

      frontend = {
        themes = {
          happy = {
            primary-color = "pink";
            accent-color = "orange";
          };
          sad = {
            primary-color = "steelblue";
            accent-color = "darkred";
          };
        };
      };
      "automation manual" = [ ];
      "automation ui" = "!include automations.yaml";
    };
  };

}
