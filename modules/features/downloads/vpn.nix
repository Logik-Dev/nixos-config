_: {
  flake.modules.nixos.vpn-torrent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.vpn.airvpn;

      ns = cfg.netns.name;
      vethHost = "veth-${ns}-host";
      vethNs = "veth-${ns}";
      cidr = addr: "${addr}/${toString cfg.netns.prefixLength}";

      ip = "${pkgs.iproute2}/bin/ip";
      sysctl = "${pkgs.procps}/bin/sysctl";

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
      # cosmetic: the equivalent `wants` on qBittorrent used to be the only thing
      # bringing the tunnel up at boot, masking an ordering cycle (see the
      # wireguard-wg0 comment below).
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

        netns = {
          name = lib.mkOption {
            type = lib.types.str;
            default = "vpn";
            description = ''
              Name of the dedicated network namespace holding the tunnel and the
              VPN-only services. Also derives the veth pair names, which the
              kernel caps at 15 characters (asserted below).
            '';
          };

          hostAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.200.0.1";
            description = ''
              Host end of the veth pair. This is the address VPN-isolated
              services reach host services on (Sonarr/Radarr, AdGuard), and the
              address Traefik is *not* reachable on — it stays on the LAN IP.
            '';
          };

          namespaceAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.200.0.2";
            description = ''
              Namespace end of the veth pair, i.e. the address host services use
              to reach qBittorrent and Prowlarr.
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
              AirVPN's in-tunnel resolver, which is what keeps their DNS inside
              the tunnel instead of leaking the queries from the WAN IP.

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
              systemd services moved into the VPN namespace. Membership is per
              *unit* and fixed at start-up, so it never depends on resolving a
              UID at runtime — which is what made the previous policy-routing
              approach able to silently drop the isolation.

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
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          # Namespace membership for the selected services. This is a separate
          # mkMerge entry, not an inline `systemd.services.<name>`, because the unit
          # names are dynamic: an attrset-level definition cannot coexist with the
          # literal `systemd.services.<name>` definitions below. Collapsing the
          # mkMerge is a Nix syntax error, not a simplification.
          { systemd.services = lib.genAttrs cfg.netns.services (_: netnsDropIn); }

          {
            # socketNamespace stays null: the encrypted transport socket lives in the
            # host namespace and follows the normal route, so no fwMark and no
            # `ip rule` are needed. Only the interface moves, which puts the default
            # route (from allowedIPsAsRoutes, table "main" by default) inside the
            # namespace — where it is the *only* default route. That is what makes
            # fail-closed structural: if the tunnel drops, there is no route at all
            # rather than a firewall rule that has to be correct.
            networking.wireguard.interfaces.wg0 = {
              ips = [ cfg.address ];
              inherit (cfg) privateKeyFile;
              inherit (cfg) mtu;
              interfaceNamespace = ns;
              # airdns returns a pool of entry IPs; re-resolving too often switches
              # the exit server (and its IP) mid-session, dropping peer connections.
              dynamicEndpointRefreshSeconds = 3600;
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

            # Prowlarr's app sync pushes indexers *to* Sonarr/Radarr, so the
            # namespace needs to reach them. They already listen on all interfaces;
            # only the host firewall was in the way. Scoped to the veth — these
            # ports stay closed on the LAN, where Traefik remains the way in.
            # Port 53 needs nothing: adguard.nix opens it globally already.
            #
            # Nothing is needed for the forwarded port either: wg0 is not in this
            # namespace, and the VPN namespace has no firewall of its own.
            networking.firewall.interfaces.${vethHost}.allowedTCPPorts = cfg.netns.hostPorts;

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
            # tunnel. Do not "fix" DNS ordering by putting it back; the cycle shows
            # up in the boot journal as "ordering cycle".
            #
            # The dependency was never needed on *this* unit: creating the
            # interface resolves no hostname (`ip link add`, `ip addr add`,
            # `wg set private-key`, `ip link set up`). Only the peer unit resolves
            # the endpoint, and it runs with WG_ENDPOINT_RESOLUTION_RETRIES=infinity
            # so `wg` waits internally until DNS answers instead of failing.
            systemd.services.wireguard-wg0 = {
              after = [ "netns-${ns}.service" ];
              requires = [ "netns-${ns}.service" ];
            };

            # Bootstrap resolver for anything run via `ip netns exec` — most
            # importantly the peer unit's `wg set … endpoint nl3.vpn.airdns.org`,
            # which resolves *inside* the namespace before the tunnel is up. Pointing
            # it at AdGuard over the veth breaks that chicken-and-egg. Note `ip netns
            # exec` bind-mounts this over /etc/resolv.conf; systemd's
            # NetworkNamespacePath does NOT, which is why the services get their own
            # BindReadOnlyPaths with the in-tunnel resolver instead.
            # An explicit mode materialises a real file rather than a store symlink.
            environment.etc."netns/${ns}/resolv.conf" = {
              mode = "0444";
              text = "nameserver ${cfg.netns.hostAddress}\n";
            };

            assertions = [
              {
                assertion = builtins.stringLength vethHost <= 15;
                message =
                  "vpn.airvpn.netns.name is too long: it derives the interface name "
                  + "'${vethHost}' (${toString (builtins.stringLength vethHost)} chars), "
                  + "and the kernel caps interface names at 15.";
              }
            ];

            # Health reporting. The tunnel had NO supervision at all until now, and
            # that blind spot is exactly how a boot failure went unnoticed: systemd
            # deleted wireguard-wg0's start job to break an ordering cycle, which
            # produces **no failed unit** — so `onFailure`/notify.services could
            # never have caught it. Fail-closed means an outage is silent by
            # design: nothing leaks, the stack simply downloads nothing.
            #
            # Runs in the HOST namespace on purpose: it needs to compare the two
            # sides (`ip netns exec` for the namespace, plain calls for the host).
            systemd.services.vpn-monitor = {
              description = "VPN tunnel health metrics (${ns})";
              after = [ "netns-${ns}.service" ];
              wants = [ "netns-${ns}.service" ];
              path = with pkgs; [
                iproute2
                wireguard-tools
                curl
                coreutils
                gawk
                gnugrep
              ];
              serviceConfig.Type = "oneshot";
              script = ''
                # `set +e` is load-bearing and must come first: NixOS prepends its
                # own `set -e` to the generated script, so writing `set -uo
                # pipefail` here does NOT disable it. Learned the hard way — with
                # the tunnel down, `wg show` failed, the script aborted before
                # writing anything, and the .prom file kept its previous values:
                # a dead tunnel reported as perfectly healthy. Every command below
                # must be allowed to fail and still reach the write at the end.
                # No `-u` either: an unbound variable kills the shell regardless
                # of `-e`, which would resurrect the same failure mode.
                set +e

                dir=/var/lib/node-exporter-textfile
                file="$dir/vpn-tunnel.prom"
                tmp="$file.tmp"

                # Unix timestamp of the last handshake, 0 if wg0 does not even
                # exist (the ordering-cycle case).
                hs=$(ip netns exec ${ns} wg show wg0 latest-handshakes 2>/dev/null | awk '{print $2}' | head -1)
                case "''${hs:-}" in "" | *[!0-9]*) hs=0 ;; esac

                # The namespace must have exactly one default route, through the
                # tunnel. Anything else means isolation is not what we think.
                if ip netns exec ${ns} ip route show default 2>/dev/null | grep -q 'dev wg0'; then
                  route=1
                else
                  route=0
                fi

                # qBittorrent binds per address and never re-binds: a wg0 recreated
                # underneath it leaves the forwarded port unreachable and the ratio
                # at zero, with no failed unit (cf. its partOf/wantedBy).
                if ip netns exec ${ns} ss -tlnH 2>/dev/null | grep -q "wg0:${toString cfg.forwardedPort}"; then
                  listener=1
                else
                  listener=0
                fi

                # End-to-end ground truth: the namespace must not exit through the
                # host's WAN address. Deliberately tolerant — if either lookup
                # fails we report the check as unusable rather than claim a leak,
                # so a flaky third party cannot page anyone at 3am.
                ns_ip=$(ip netns exec ${ns} curl -s --max-time 10 https://api.ipify.org 2>/dev/null)
                host_ip=$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null)
                if [ -n "$ns_ip" ] && [ -n "$host_ip" ]; then
                  check=1
                  if [ "$ns_ip" = "$host_ip" ]; then isolated=0; else isolated=1; fi
                else
                  check=0
                  isolated=1
                fi

                {
                  printf 'vpn_tunnel_handshake_timestamp_seconds %s\n' "$hs"
                  printf 'vpn_tunnel_default_route %s\n' "$route"
                  printf 'vpn_tunnel_listener_bound %s\n' "$listener"
                  printf 'vpn_exit_ip_check_success %s\n' "$check"
                  printf 'vpn_exit_ip_isolated %s\n' "$isolated"
                  printf 'vpn_monitor_timestamp_seconds %s\n' "$(date +%s)"
                } > "$tmp"
                mv -f "$tmp" "$file"
              '';
            };

            systemd.timers.vpn-monitor = {
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "*:0/5";
                RandomizedDelaySec = "1m";
                Persistent = true;
              };
            };

            notify.services = [ "vpn-monitor" ];

            # Persistent, never-recreated network namespace. Everything about this
            # unit is deliberate:
            #  - no sandboxing options: `ip netns add` creates a bind mount under
            #    /run/netns that must be visible in the host mount namespace, which
            #    ProtectSystem/PrivateMounts/PrivateTmp would hide;
            #  - RemainAfterExit, and no preStop: the namespace must outlive both the
            #    tunnel and this unit's own restarts;
            #  - idempotent, and it never deletes the namespace (see below).
            systemd.services."netns-${ns}" = {
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
                # exactly the failure mode this design exists to remove. A leftover
                # /run/netns entry that is somehow unusable can only survive within
                # one boot (/run is tmpfs); recover by rebooting, not by deleting.
                if [ ! -e /run/netns/${ns} ]; then
                  ${ip} netns add ${ns}
                fi

                # Every namespace gets its own loopback, DOWN by default. Without
                # this the qBittorrent WebUI and the cross-seed -> qBittorrent calls
                # (both 127.0.0.1) fail.
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

                # Pin the veth to its peer: nothing may leave it except towards the
                # host end of the /30.
                #
                # Defensive today — the counter sits at zero. It earned its keep at
                # setup time by exposing a real problem: qBittorrent used to bind a
                # listener to every interface in the namespace, the veth included
                # (`ss -tlnp` showed `10.200.0.2%veth-vpn:47594`, i.e.
                # SO_BINDTODEVICE), and sent peer/DHT UDP from it towards public
                # addresses — ~460 packets in the 40s after a tunnel restart. Never
                # a leak (10.200.0.0/30 is not masqueraded, netavark's MASQUERADE
                # being scoped to 10.88.0.0/16, and tcpdump on the WAN link showed
                # zero packets with that source), just dead traffic sprayed at the
                # host. Fixed at the source by pointing qBittorrent's network
                # interface at wg0 (Options -> Advanced) — safe since the namespace
                # resolves through the tunnel, unlike before the migration. If this
                # counter starts climbing again, check that setting first.
                #
                # It also closes the one residual escape route: the host forwards
                # (net.ipv4.conf.all.forwarding, set by tailscale's
                # useRoutingFeatures), so a stray route added in here later would
                # otherwise have a path out. Verified by adding a route to the LAN
                # by hand — reachable without this rule, dropped with it.
                #
                # Safe to run nftables *here* even though the host firewall is
                # iptables-based and `networking.nftables.enable` must stay off
                # (it would break libvirt/podman): rules are per-namespace, and
                # this namespace has no other firewall at all. Deliberately no
                # matching `forward` drop on the host side — nothing can be
                # forwarded that this rule does not already stop at the source,
                # and a host-side forward hook is exactly what risks libvirt.
                #
                # policy accept + a single drop: wg0 and lo stay untouched. To see
                # what is being dropped, the counter is enough; nft `log` from a
                # non-init namespace is silently discarded unless
                # net.netfilter.nf_log_all_netns=1 is set on the host.
                ${ip} netns exec ${ns} ${pkgs.nftables}/bin/nft delete table inet vpn_guard 2>/dev/null || true
                ${ip} netns exec ${ns} ${pkgs.nftables}/bin/nft -f - <<EOF
                table inet vpn_guard {
                  chain output {
                    type filter hook output priority 0; policy accept;
                    oifname "${vethNs}" ip daddr != ${cfg.netns.hostAddress} counter drop
                  }
                }
                EOF
              '';
            };
          }
        ]
      );
    };
}
