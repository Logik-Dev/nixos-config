{ inputs, ... }:
{
  flake.modules.nixos.ddns =
    {
      config,
      ...
    }:
    {
      imports = [
        inputs.cf-ddns.nixosModules.x86_64-linux.default
      ];

      services.cf-ddns = {
        enable = true;
        environmentFile = config.age.secrets."ddns.env".path;
      };

      systemd.timers."cf-ddns" = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "5m";
          Unit = "cf-ddns.service";
        };
      };
    };
}
