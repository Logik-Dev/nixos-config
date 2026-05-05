{
  flake.modules.nixos.mosquitto = {
    services.mosquitto = {
      enable = true;
      listeners = [
        {
          address = "0.0.0.0";
          port = 1883;
          acl = [ "pattern readwrite #" ];
          omitPasswordAuth = true;
          settings.allow_anonymous = true;
        }
      ];
    };
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 1883 ];
    };
  };
}
