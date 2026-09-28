_: {
  flake.modules.nixos.vpn-torrent =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.vpn.airvpn;

      useNetns = cfg.isolation == "netns";
      ns = cfg.netns.name;
      vethHost = "veth-${ns}-host";
      vethNs = "veth-${ns}";
      cidr = addr: "${addr}/${toString cfg.netns.prefixLength}";

      ip = "${pkgs.iproute2}/bin/ip";
      sysctl = "${pkgs.procps}/bin/sysctl";

      # Options that only mean something in `uid` mode, and whether anyone has
      # actually customised them (see the assertion below for why this is a
      # value-vs-default comparison and not `isDefined`).
      uidOnlyOptions = [
        "routedUsers"
        "lanNetworks"
        "tailscaleNetworksV4"
        "tailscaleNetworksV6"
      ];
      customisedUidOptions = lib.filter (
        name: cfg.${name} != options.vpn.airvpn.${name}.default
      ) uidOnlyOptions;

      # In-tunnel resolver for the services inside the namespace. systemd's
      # NetworkNamespacePath does NOT bind-mount /etc/netns/<ns>/*, so each unit
      # needs this bound over /etc/resolv.conf explicitly.
      appResolvConf = pkgs.writeText "vpn-netns-resolv.conf" ''
        nameserver ${cfg.netns.resolver}
      '';

      # Shared drop-in for every service that lives in the namespace, rather than
      # repeating it across qbittorrent.nix / cross-seed.nix / freeleech-farmer.nix.
      # Requires (not just After) on the namespace: without /run/netns/<ns> the
      # unit cannot even fork.
      #
      # `wants` on the tunnel, never `requires`: a weak dependency pulls wg0 up if
      # nothing else did, while still letting the service start when the tunnel is
      # down — it simply fails closed, which is the whole point. This is not
      # cosmetic: the equivalent `wants` on qBittorrent in uid mode turned out to
      # be the only thing bringing the tunnel up at boot, masking an ordering
      # cycle (see the wireguard-wg0 comment below).
      netnsDropIn = {
        after = [
          "netns-${ns}.service"
          "wireguard-wg0.service"
        ];
        wants = [ "wireguard-wg0.service" ];
        requires = [ "netns-${ns}.service" ];
        serviceConfig = {
          NetworkNamespacePath = "/run/netns/${ns}";
          BindReadOnlyPaths = [ "${appResolvConf}:/etc/resolv.conf" ];
        };
      };
    in
    {
      options.vpn.airvpn = {
        enable = lib.mkEnableOption "AirVPN WireGuard tunnel for torrenting";

        isolation = lib.mkOption {
          type = lib.types.enum [
            "uid"
            "netns"
          ];
          default = "uid";
          description = ''
            How VPN-only traffic is kept off the WAN.

            `uid` (current): wg0 lives in the host namespace, routed users are
            selected by `ip rule uidrange` into table 4242 and an nftables
            kill-switch drops anything of theirs that would leave elsewhere.
            Depends on resolving UIDs at runtime, which is fragile: a routed
            service restarting (or Prowlarr's DynamicUser getting a new UID)
            can silently drop the rules.

            `netns`: wg0 is moved into a dedicated network namespace whose only
            default route is the tunnel, so fail-closed is structural rather
            than rule-based. Migration plan: `docs/vpn-netns-plan.md`.

            Set back to `uid` to roll the migration back.
          '';
        };

        netns = {
          name = lib.mkOption {
            type = lib.types.str;
            default = "vpn";
            description = ''
              Name of the dedicated network namespace (`isolation = "netns"`).
              Also derives the veth pair names, which the kernel caps at 15
              characters (asserted below).
            '';
          };

          hostAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.200.0.1";
            description = ''
              Host end of the veth pair. This is the address VPN-isolated
              services reach host services on (Sonarr/Radarr, AdGuard), and the
              address Traefik is *not* reachable on — it stays on localhost.
            '';
          };

          namespaceAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.200.0.2";
            description = ''
              Namespace end of the veth pair, i.e. the address host services use
              to reach qBittorrent/Prowlarr once they move (lot B).
            '';
          };

          prefixLength = lib.mkOption {
            type = lib.types.int;
            default = 30;
            description = ''
              Prefix length of the veth link network. A /30 is deliberate: the
              connected route covers the peer only, so the namespace has no way
              to reach the LAN or the WAN over the veth.
            '';
          };

          resolver = lib.mkOption {
            type = lib.types.str;
            default = "10.128.0.1";
            description = ''
              DNS server used by the services inside the namespace. Defaults to
              AirVPN's in-tunnel resolver, which is what finally tunnels their
              DNS (in `uid` mode they resolved via AdGuard from the WAN IP).

              Distinct from the bootstrap resolver in
              /etc/netns/<name>/resolv.conf: that one must be reachable *before*
              the tunnel exists, because `wg` resolves the AirVPN endpoint from
              inside the namespace.
            '';
          };

          hostPorts = lib.mkOption {
            type = lib.types.listOf lib.types.port;
            default = [
              8989 # Sonarr  — Prowlarr app sync pushes indexers to it
              7878 # Radarr  — idem
            ];
            description = ''
              Host TCP ports opened on the veth for the namespace. Deliberately
              scoped to that interface: these services stay unreachable from the
              LAN, where Traefik remains the only entry point.
            '';
          };

          services = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              systemd services moved into the VPN namespace. This is the `netns`
              mode equivalent of `routedUsers`: membership is per *unit*, fixed
              at start-up, and no longer depends on resolving a UID at runtime.

              Each module appends itself (see qbittorrent.nix, prowlarr.nix,
              cross-seed.nix, freeleech-farmer.nix) so that a conditionally
              enabled service cannot leave a phantom unit behind (cf. FAC-5).

              The default is deliberately empty: a default is NOT a definition,
              so any module contributing to this list would silently *replace* a
              non-empty default instead of extending it — which would leave
              services outside the namespace with nothing protecting them.
            '';
          };
        };

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

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          # Move the selected services into the namespace. This replaces the entire
          # UID-based mechanism: no `ip rule`, no kill-switch, no UID resolution, and
          # therefore none of the failure modes that came with it (a routed service
          # restarting, or Prowlarr's DynamicUser getting a new UID, can no longer
          # silently drop the isolation). Separate mkMerge entry because the unit
          # names are dynamic, so this has to be an attrset-level definition.
          (lib.mkIf useNetns { systemd.services = lib.genAttrs cfg.netns.services (_: netnsDropIn); })

          {
            networking.wireguard.interfaces.wg0 = {
              ips = [ cfg.address ];
              inherit (cfg) privateKeyFile;
              inherit (cfg) mtu;
              # airdns returns a pool of entry IPs; re-resolving too often switches
              # the exit server (and its IP) mid-session, dropping peer connections.
              dynamicEndpointRefreshSeconds = 3600;
            }
            // lib.optionalAttrs (!useNetns) {
              table = "4242";
              # Marks the encrypted WireGuard transport packets so the kill-switch and
              # policy routing never confuse them with tunneled app traffic. Tied to
              # the kill-switch's lifetime, not to the tunnel's: the transport socket
              # stays in the host namespace even in netns mode (only the interface
              # moves), so while the kill-switch existed there, these kernel-generated
              # packets — no skuid to match, and `oifname "wg0"` unmatchable once wg0
              # has left — fell through onto `counter drop` and the handshake never
              # left the box. Both go away together in netns mode.
              fwMark = "0x4242";
            }
            // lib.optionalAttrs useNetns {
              # socketNamespace stays null: the encrypted transport socket lives in
              # the host namespace and follows the normal route, so no fwMark and no
              # `ip rule` are needed. Only the interface moves, which puts the
              # default route (from allowedIPsAsRoutes, table "main" by default)
              # inside the namespace — where it is the *only* default route.
              interfaceNamespace = ns;
            }
            // {
              peers = [
                (
                  {
                    inherit (cfg) publicKey;
                    allowedIPs = [ "0.0.0.0/0" ];
                    inherit (cfg) endpoint;
                    persistentKeepalive = 15;
                  }
                  // lib.optionalAttrs (cfg.presharedKeyFile != null) {
                    inherit (cfg) presharedKeyFile;
                  }
                )
              ];
            };

            # Allow the AirVPN forwarded port only on the VPN interface. Dead config
            # in netns mode: wg0 no longer exists in the host namespace, and the
            # namespace has no firewall of its own, so ingress is already allowed.
            networking.firewall.interfaces = lib.mkMerge [
              (lib.mkIf (!useNetns) {
                wg0 = {
                  allowedTCPPorts = [ cfg.forwardedPort ];
                  allowedUDPPorts = [ cfg.forwardedPort ];
                };
              })
              # Prowlarr's app sync pushes indexers *to* Sonarr/Radarr, so the
              # namespace needs to reach them. They already listen on all interfaces;
              # only the host firewall was in the way. Scoped to the veth — these
              # ports stay closed on the LAN, where Traefik remains the way in.
              # Port 53 needs nothing: adguard.nix opens it globally already.
              (lib.mkIf useNetns {
                ${vethHost}.allowedTCPPorts = cfg.netns.hostPorts;
              })
            ];

            # Strict reverse-path filtering breaks WireGuard ingress for P2P peers.
            # Only needed while wg0 lives in the host namespace: this is implemented
            # as an iptables `-m rpfilter` rule in mangle/PREROUTING, and iptables
            # rules are per-network-namespace — so in netns mode there is no rpfilter
            # in front of wg0 at all and nothing to loosen. Dropping the definition
            # here changes nothing on the host either way: tailscale's
            # useRoutingFeatures = "both" pins it to "loose" with a plain (non-default)
            # definition. Two equal definitions merge; a differing one fails eval.
            networking.firewall.checkReversePath = lib.mkIf (!useNetns) "loose";

            # The netns must exist before the interface can be moved into it, and
            # Requires (not just After) so a failed namespace setup fails the
            # tunnel loudly instead of leaving a half-configured host.
            #
            # Deliberately NO ordering on adguardhome here, despite this unit
            # having carried `after = [ "adguardhome.service" ]` for a long time.
            # That created a systemd ordering cycle — wireguard-wg0 after
            # adguardhome, adguardhome after network.target, and the nixpkgs module
            # puts wireguard-wg0 *before* network.target — which systemd resolved
            # by **deleting the tunnel's own start job**: no failed unit, just no
            # tunnel. It went unnoticed because qBittorrent used to carry
            # `wants = [ "wireguard-wg0.service" ]`, which pulled the tunnel up
            # after the fact; the cycle is visible in `journalctl -b | grep
            # "ordering cycle"`.
            #
            # The dependency was never needed on *this* unit: creating the
            # interface resolves no hostname (`ip link add`, `ip addr add`,
            # `wg set private-key`, `ip link set up`). Only the peer unit resolves
            # the endpoint, and it runs with WG_ENDPOINT_RESOLUTION_RETRIES=infinity
            # so `wg` waits internally until DNS answers instead of failing.
            systemd.services.wireguard-wg0 = lib.mkIf useNetns {
              after = [ "netns-${ns}.service" ];
              requires = [ "netns-${ns}.service" ];
            };

            # Bootstrap resolver for anything run via `ip netns exec` — most
            # importantly the peer unit's `wg set … endpoint nl3.vpn.airdns.org`,
            # which resolves *inside* the namespace before the tunnel is up. Pointing
            # it at AdGuard over the veth breaks that chicken-and-egg. Note `ip netns
            # exec` bind-mounts this over /etc/resolv.conf; systemd's
            # NetworkNamespacePath does NOT, so services moved in lot B need their
            # own BindReadOnlyPaths (they will get the in-tunnel resolver instead).
            # An explicit mode materialises a real file rather than a store symlink.
            environment.etc."netns/${ns}/resolv.conf" = lib.mkIf useNetns {
              mode = "0444";
              text = "nameserver ${cfg.netns.hostAddress}\n";
            };

            assertions = lib.optionals useNetns [
              {
                assertion = builtins.stringLength vethHost <= 15;
                message =
                  "vpn.airvpn.netns.name is too long: it derives the interface name "
                  + "'${vethHost}' (${toString (builtins.stringLength vethHost)} chars), "
                  + "and the kernel caps interface names at 15.";
              }
              {
                # The UID machinery is inert in netns mode, so customising it
                # would be a silent no-op: someone adding a service to
                # routedUsers would believe it is VPN-isolated when nothing of
                # the sort happened. Membership is per-unit here — use
                # vpn.airvpn.netns.services instead.
                #
                # Compared against the declared defaults rather than using
                # `options.<…>.isDefined`: a default counts as a definition (the
                # declaring file shows up in its `files`), so isDefined is true
                # even for an option nobody ever touched.
                assertion = customisedUidOptions == [ ];
                message =
                  "vpn.airvpn: ${lib.concatStringsSep ", " customisedUidOptions} "
                  + "only applies to isolation = \"uid\" and is ignored with "
                  + "isolation = \"netns\". Add the *service* to "
                  + "vpn.airvpn.netns.services instead (see docs/vpn-netns-plan.md).";
              }
            ];

            # Persistent, never-recreated network namespace. Everything about this
            # unit is deliberate:
            #  - no sandboxing options: `ip netns add` creates a bind mount under
            #    /run/netns that must be visible in the host mount namespace, which
            #    ProtectSystem/PrivateMounts/PrivateTmp would hide;
            #  - RemainAfterExit, and no preStop: the namespace must outlive both the
            #    tunnel and this unit's own restarts;
            #  - idempotent, and it never deletes the namespace (see below).
            systemd.services."netns-${ns}" = lib.mkIf useNetns {
              description = "Persistent network namespace for VPN-isolated services (${ns})";
              after = [ "network-pre.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                set -euo pipefail

                # NEVER delete and recreate the namespace: services attached to it
                # via NetworkNamespacePath would keep a stale, routeless namespace
                # and fail *silently* — a running qBittorrent with no network is
                # exactly the failure mode this migration exists to remove. A leftover
                # /run/netns entry that is somehow unusable can only survive within
                # one boot (/run is tmpfs); recover by rebooting, not by deleting.
                if [ ! -e /run/netns/${ns} ]; then
                  ${ip} netns add ${ns}
                fi

                # Every namespace gets its own loopback, DOWN by default. Without
                # this the qBittorrent WebUI and cross-seed -> qBittorrent calls
                # (both 127.0.0.1) fail once those services move in lot B.
                ${ip} -n ${ns} link set lo up

                # veth pair: the only path across the boundary besides the tunnel.
                # Recreating the veth is safe (unlike the namespace), so heal it as a
                # pair whenever the namespace side is missing.
                if ! ${ip} -n ${ns} link show ${vethNs} >/dev/null 2>&1; then
                  ${ip} link del ${vethHost} 2>/dev/null || true
                  ${ip} link add ${vethHost} type veth peer name ${vethNs} netns ${ns}
                fi

                # `addr replace` is idempotent. Deliberately no default route over
                # the veth: only the connected /30 is reachable, so the namespace
                # cannot reach the LAN or the WAN this way even with the tunnel down.
                ${ip} addr replace ${cidr cfg.netns.hostAddress} dev ${vethHost}
                ${ip} link set ${vethHost} up
                ${ip} -n ${ns} addr replace ${cidr cfg.netns.namespaceAddress} dev ${vethNs}
                ${ip} -n ${ns} link set ${vethNs} up

                # AirVPN hands out an IPv4 /32 only, so the namespace has no IPv6
                # route and IPv6 already fails closed. Disabling it makes that
                # explicit rather than incidental.
                ${ip} netns exec ${ns} ${sysctl} -q -w net.ipv6.conf.all.disable_ipv6=1
                ${ip} netns exec ${ns} ${sysctl} -q -w net.ipv6.conf.default.disable_ipv6=1
              '';
            };

            # The two UID-based units below belong to `isolation = "uid"` only. They
            # are kept (rather than deleted) so that setting isolation back to "uid"
            # is a genuine one-line rollback. Note they must never be removed in the
            # same step as moving the services *out* of the host namespace, nor left
            # behind after it: during lot A, with wg0 already in the namespace but the
            # services still outside, they were what kept those services fail-closed
            # instead of leaking out of the WAN.
            # Route selected users through the VPN routing table.
            systemd.services.vpn-policy-routing = lib.mkIf (!useNetns) {
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
              # `partOf` stops us whenever Prowlarr stops (e.g. the nightly restic
              # backup does `systemctl stop prowlarr`), but the follow-up `start`
              # does not pull us back up — hence the explicit wantedBy, so starting
              # Prowlarr re-applies the rules (and the kill-switch stays up).
              wantedBy = [
                "multi-user.target"
                "prowlarr.service"
              ];
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
            systemd.services.vpn-killswitch = lib.mkIf (!useNetns) {
              description = "nftables kill-switch for VPN-torrent users";
              after = [ "vpn-policy-routing.service" ];
              before = [
                "qbittorrent.service"
                "cross-seed.service"
              ];
              partOf = [ "prowlarr.service" ];
              wants = [ "vpn-policy-routing.service" ];
              wantedBy = [
                "multi-user.target"
                "prowlarr.service"
              ];
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
          }
        ]
      );
    };
}
