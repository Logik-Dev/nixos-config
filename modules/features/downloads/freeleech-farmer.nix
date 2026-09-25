{ inputs, ... }:
{
  flake.modules.nixos.freeleech-farmer =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      farmer = pkgs.writeShellApplication {
        name = "freeleech-farmer";
        runtimeInputs = [ pkgs.python3 ];
        text = "exec python3 ${./freeleech-farmer.py}";
      };
    in
    {
      # Reuses the cross-seed secret (torznab URLs + qBittorrent credentials)
      # and its user (uid already routed through the VPN + kill-switch).
      config = lib.mkIf (config.age.secrets ? "cross-seed-secrets.json") {
        systemd.services.freeleech-farmer = {
          description = "Freeleech ratio farmer";
          after = [
            "cross-seed.service"
            "vpn-killswitch.service"
          ];
          unitConfig.RequiresMountsFor = [ "/mnt/storage" ];
          serviceConfig = {
            Type = "oneshot";
            User = "cross-seed";
            Group = "media";
            LoadCredential = "crossSeedSecret:${config.age.secrets."cross-seed-secrets.json".path}";
            ExecStart = "${farmer}/bin/freeleech-farmer";
            Environment = [
              "FARMER_MAX_ADDS=5"
              "FARMER_MIN_SEEDERS=1"
              "FARMER_MAX_SIZE_GB=20"
              "FARMER_MAX_TOTAL_GB=100"
              "FARMER_MIN_FREE_GB=200"
              "FARMER_CLEAN_RATIO=2.0"
              "FARMER_CLEAN_DAYS=14"
            ];
          };
        };

        systemd.timers.freeleech-farmer = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*:0/30";
            RandomizedDelaySec = "2m";
            Persistent = true;
          };
        };

        systemd.tmpfiles.rules = [
          "d /mnt/storage/medias/downloads/freeleech 2775 qbittorrent media - -"
        ];

        notify.services = [ "freeleech-farmer" ];
      };
    };
}
