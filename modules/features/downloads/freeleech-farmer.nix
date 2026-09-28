_: {
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
          # The VPN ordering (namespace + tunnel) comes from the shared drop-in in
          # vpn.nix, which this unit gets by being in vpn.airvpn.netns.services.
          after = [
            "cross-seed.service"
            "qbittorrent.service"
          ];
          wants = [ "qbittorrent.service" ];
          unitConfig.RequiresMountsFor = [ "/mnt/storage" ];
          serviceConfig = {
            Type = "oneshot";
            User = "cross-seed";
            Group = "media";
            LoadCredential = "crossSeedSecret:${config.age.secrets."cross-seed-secrets.json".path}";
            ExecStart = "${farmer}/bin/freeleech-farmer";
            Environment = [
              "FARMER_MAX_ADDS=15"
              "FARMER_MIN_SEEDERS=1"
              # 0 = accept any freeleech, but sort by leechers so items that can
              # actually be uploaded are picked first.
              "FARMER_MIN_LEECHERS=0"
              "FARMER_MAX_SIZE_GB=20"
              "FARMER_MAX_TOTAL_GB=300"
              "FARMER_MIN_FREE_GB=200"
              "FARMER_CLEAN_RATIO=3.0"
              "FARMER_CLEAN_DAYS=30"
            ];
          };
        };

        systemd.timers.freeleech-farmer = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*:0/10";
            RandomizedDelaySec = "2m";
            Persistent = true;
          };
        };

        systemd.tmpfiles.rules = [
          "d /mnt/storage/medias/downloads/freeleech 2775 qbittorrent media - -"
        ];

        notify.services = [ "freeleech-farmer" ];

        # Same rationale as cross-seed.nix: the unit only exists when this module
        # is enabled, so it adds itself to the namespace rather than being listed
        # in vpn.nix (which would create a phantom unit, cf. FAC-5).
        vpn.airvpn.netns.services = [ "freeleech-farmer" ];
      };
    };
}
