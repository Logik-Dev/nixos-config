{
  flake.modules.nixos.smartd = {
    notify.services = [ "smartd" ];

    services.smartd = {
      enable = true;
      autodetect = true;
      notifications = {
        mail.enable = false;
        wall.enable = true;
        test = true;
      };
    };
  };
}
