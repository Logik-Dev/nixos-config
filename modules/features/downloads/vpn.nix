{ inputs, ... }:
{
  flake.modules.nixos.vpn-torrent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.vpn.airvpn;
    in
    {
      options.vpn.airvpn = {
        enable = lib.mkEnableOption "AirVPN WireGuard tunnel for torrenting";

        address = lib.mkOption {
          type = lib.types.str;
          example = "10.45.95.123/32";
          description = "WireGuard client address (with CIDR) from the AirVPN config";
        };

        publicKey = lib.mkOption {
          type = lib.types.str;
          description = "AirVPN server public key";
        };

        endpoint = lib.mkOption {
          type = lib.types.str;
          example = "nl3.vpn.airdns.org:1637";
          description = "AirVPN server endpoint";
        };

        forwardedPort = lib.mkOption {
          type = lib.types.port;
          default = 51413;
          description = "AirVPN forwarded port (local listening port on this machine)";
        };

        mtu = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = 1320;
          description = "WireGuard MTU (AirVPN default is 1320)";
        };

        privateKeyFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to the WireGuard private key file";
        };

        presharedKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Optional path to the WireGuard preshared key file";
        };

        routedUsers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "qbittorrent"
            "prowlarr"
            "cross-seed"
          ];
          description = "User names whose traffic is forced through the VPN tunnel";
        };

        lanNetworks = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "192.168.10.0/24"
            "192.168.21.0/24"
          ];
          description = ''
            Networks that routed users can reach directly (not via VPN).
            Do NOT add Tailscale's 100.64.0.0/10 here: forcing it to the main
            table overrides Tailscale's own policy routing and breaks the mesh.
            Tailscale is handled by tailscaleNetworksV4/V6 instead.
          '';
        };

        tailscaleNetworksV4 = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "100.64.0.0/10" ];
          description = ''
            Tailscale IPv4 ranges routed users may reach via Tailscale's own
            table 52. Required because Tailscale MagicDNS (100.100.100.100) is
            the system resolver: without it, DNS queries from routed users are
            sent into the VPN tunnel and time out (EAI_AGAIN).
          '';
        };

        tailscaleNetworksV6 = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "fd7a:115c:a1e0::/48" ];
          description = "Tailscale IPv6 range, same purpose as tailscaleNetworksV4.";
        };
      };

      config = lib.mkIf cfg.enable {
        networking.wireguard.interfaces.wg0 = {
          ips = [ cfg.address ];
          privateKeyFile = cfg.privateKeyFile;
          inherit (cfg) mtu;
          table = "4242";
          # Marks the encrypted WireGuard transport packets so the kill-switch
          # and policy routing never confuse them with tunneled app traffic.
          fwMark = "0x4242";
          dynamicEndpointRefreshSeconds = 300;
          peers = [
            (
              {
                publicKey = cfg.publicKey;
                allowedIPs = [ "0.0.0.0/0" ];
                endpoint = cfg.endpoint;
                persistentKeepalive = 15;
              }
              // lib.optionalAttrs (cfg.presharedKeyFile != null) {
                presharedKeyFile = cfg.presharedKeyFile;
              }
            )
          ];
        };

        # Allow the AirVPN forwarded port only on the VPN interface.
        networking.firewall.interfaces.wg0 = {
          allowedTCPPorts = [ cfg.forwardedPort ];
          allowedUDPPorts = [ cfg.forwardedPort ];
        };

        # Strict reverse-path filtering breaks WireGuard ingress for P2P peers.
        networking.firewall.checkReversePath = "loose";

        # Ensure AdGuard is up before WireGuard tries to resolve the endpoint
        # hostname, otherwise `wg` may retry DNS indefinitely and block activation.
        systemd.services.wireguard-wg0 = {
          after = [ "adguardhome.service" ];
          wants = [ "adguardhome.service" ];
        };

        # Route selected users through the VPN routing table.
        systemd.services.vpn-policy-routing = {
          description = "Policy routing for VPN-torrent users";
          # Prowlarr is a DynamicUser: its UID only exists once the unit starts,
          # so ordering after it lets us resolve and route it correctly. partOf
          # re-applies the rules whenever Prowlarr (re)starts with a new UID.
          after = [
            "wireguard-wg0.service"
            "prowlarr.service"
          ];
          before = [
            "qbittorrent.service"
            "cross-seed.service"
          ];
          partOf = [ "prowlarr.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -euo pipefail

            # Clean up rules left by previous versions (they were global and
            # overrode Tailscale's own policy routing). `ip rule del` removes
            # only one matching rule per call, so loop until none remain.
            while ${pkgs.iproute2}/bin/ip rule del lookup 4242 2>/dev/null; do :; done
            while ${pkgs.iproute2}/bin/ip -6 rule del lookup 4242 2>/dev/null; do :; done
            ${lib.concatMapStringsSep "\n" (net: ''
              ${pkgs.iproute2}/bin/ip rule del to ${net} lookup main pref 100 || true
            '') cfg.lanNetworks}

            # WireGuard transport packets carry fwMark 0x4242 and must always
            # follow the main table, never the VPN table.
            while ${pkgs.iproute2}/bin/ip rule del fwmark 0x4242 lookup main pref 50 2>/dev/null; do :; done
            while ${pkgs.iproute2}/bin/ip -6 rule del fwmark 0x4242 lookup main pref 50 2>/dev/null; do :; done
            ${pkgs.iproute2}/bin/ip rule add fwmark 0x4242 lookup main pref 50
            ${pkgs.iproute2}/bin/ip -6 rule add fwmark 0x4242 lookup main pref 50

            # Scope routing exceptions to the torrent users only, so SSH,
            # Tailscale and containers keep the kernel's normal rules.
            for user in ${lib.concatStringsSep " " cfg.routedUsers}; do
              uid=$(${pkgs.coreutils}/bin/id -u "$user" 2>/dev/null) || {
                echo "vpn-policy-routing: user $user not found, skipping"
                continue
              }
              for net in ${lib.concatStringsSep " " cfg.lanNetworks}; do
                ${pkgs.iproute2}/bin/ip rule del uidrange "$uid-$uid" to "$net" lookup main pref 100 || true
              done
              for net in ${lib.concatStringsSep " " cfg.tailscaleNetworksV4}; do
                ${pkgs.iproute2}/bin/ip rule del uidrange "$uid-$uid" to "$net" lookup 52 pref 100 || true
              done
              for net in ${lib.concatStringsSep " " cfg.tailscaleNetworksV6}; do
                ${pkgs.iproute2}/bin/ip -6 rule del uidrange "$uid-$uid" to "$net" lookup 52 pref 100 || true
              done
              ${pkgs.iproute2}/bin/ip rule del uidrange "$uid-$uid" lookup 4242 pref 200 || true
              for net in ${lib.concatStringsSep " " cfg.lanNetworks}; do
                ${pkgs.iproute2}/bin/ip rule add uidrange "$uid-$uid" to "$net" lookup main pref 100
              done
              for net in ${lib.concatStringsSep " " cfg.tailscaleNetworksV4}; do
                ${pkgs.iproute2}/bin/ip rule add uidrange "$uid-$uid" to "$net" lookup 52 pref 100
              done
              for net in ${lib.concatStringsSep " " cfg.tailscaleNetworksV6}; do
                ${pkgs.iproute2}/bin/ip -6 rule add uidrange "$uid-$uid" to "$net" lookup 52 pref 100
              done
              ${pkgs.iproute2}/bin/ip rule add uidrange "$uid-$uid" lookup 4242 pref 200
            done
          '';
          preStop = ''
            # Also clean up global rules applied by older versions of this unit.
            while ${pkgs.iproute2}/bin/ip rule del lookup 4242 2>/dev/null; do :; done
            while ${pkgs.iproute2}/bin/ip -6 rule del lookup 4242 2>/dev/null; do :; done
            while ${pkgs.iproute2}/bin/ip rule del fwmark 0x4242 lookup main pref 50 2>/dev/null; do :; done
            while ${pkgs.iproute2}/bin/ip -6 rule del fwmark 0x4242 lookup main pref 50 2>/dev/null; do :; done
            ${lib.concatMapStringsSep "\n" (net: ''
              ${pkgs.iproute2}/bin/ip rule del to ${net} lookup main pref 100 || true
            '') cfg.lanNetworks}

            for user in ${lib.concatStringsSep " " cfg.routedUsers}; do
              uid=$(${pkgs.coreutils}/bin/id -u "$user" 2>/dev/null) || continue
              for net in ${lib.concatStringsSep " " cfg.lanNetworks}; do
                ${pkgs.iproute2}/bin/ip rule del uidrange "$uid-$uid" to "$net" lookup main pref 100 || true
              done
              for net in ${lib.concatStringsSep " " cfg.tailscaleNetworksV4}; do
                ${pkgs.iproute2}/bin/ip rule del uidrange "$uid-$uid" to "$net" lookup 52 pref 100 || true
              done
              for net in ${lib.concatStringsSep " " cfg.tailscaleNetworksV6}; do
                ${pkgs.iproute2}/bin/ip -6 rule del uidrange "$uid-$uid" to "$net" lookup 52 pref 100 || true
              done
              ${pkgs.iproute2}/bin/ip rule del uidrange "$uid-$uid" lookup 4242 pref 200 || true
            done
          '';
        };

        # Drop any traffic from routed users that does not leave through wg0.
        systemd.services.vpn-killswitch = {
          description = "nftables kill-switch for VPN-torrent users";
          after = [ "vpn-policy-routing.service" ];
          before = [
            "qbittorrent.service"
            "cross-seed.service"
          ];
          partOf = [ "prowlarr.service" ];
          wants = [ "vpn-policy-routing.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -euo pipefail

            uids=""
            for user in ${lib.concatStringsSep " " cfg.routedUsers}; do
              uid=$(${pkgs.coreutils}/bin/id -u "$user" 2>/dev/null) || {
                echo "vpn-killswitch: user $user not found, skipping"
                continue
              }
              if [ -z "$uids" ]; then
                uids="$uid"
              else
                uids="$uids, $uid"
              fi
            done

            if ${pkgs.nftables}/bin/nft list table inet vpn_killswitch >/dev/null 2>&1; then
              ${pkgs.nftables}/bin/nft delete table inet vpn_killswitch
            fi

            ${pkgs.nftables}/bin/nft -f - <<EOF
            table inet vpn_killswitch {
              chain output {
                type filter hook output priority 0; policy accept;
                meta mark 0x4242 accept
                meta skuid != { $uids } accept
                oifname "lo" accept
                ${lib.concatMapStringsSep "\n                " (net: ''
                  ip daddr ${net} accept
                '') cfg.lanNetworks}
                ${lib.concatMapStringsSep "\n                " (net: ''
                  ip daddr ${net} accept
                '') cfg.tailscaleNetworksV4}
                ${lib.concatMapStringsSep "\n                " (net: ''
                  ip6 daddr ${net} accept
                '') cfg.tailscaleNetworksV6}
                oifname "wg0" accept
                counter drop
              }
            }
            EOF
          '';
          preStop = ''
            ${pkgs.nftables}/bin/nft delete table inet vpn_killswitch || true
          '';
        };
      };
    };
}
