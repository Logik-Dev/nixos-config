# SEC-14 — close the unfiltered path from the IoT VLAN into the LAN.
#
# hyper has a leg on both sides: `management` (192.168.10.100) and the IoT
# bridge `br-iot` (192.168.21.241). ip_forward is on — Tailscale turns it on for
# the subnet router — and the FORWARD chain has policy ACCEPT, because
# `networking.firewall` only ever filters INPUT. An IoT device that points its
# default route at 192.168.21.241 therefore reaches the LAN *without the UniFi
# inter-VLAN rules ever seeing the packets*. Verified 2026-09-29 with a
# throwaway netns on br-iot: ping and TCP/443 to 192.168.10.1 both succeeded.
#
# Why raw iptables and not `networking.firewall.filterForward`: that option is
# nftables-only and hyper runs the iptables backend. Flipping the host to
# nftables *and* the FORWARD policy to drop would also take down Tailscale
# subnet routing, netavark (immich) and the vpn netns veth until explicit rules
# are written for each — a separate piece of work, see docs/security.md. This is
# the targeted half, and it is deliberately narrow.
#
# Scope, stated honestly:
#   - covered: IoT -> LAN, IoT -> podman network, IoT -> the vpn netns veth.
#   - NOT covered: IoT -> tailnet. The jump is appended, so ts-forward runs
#     first and it accepts everything leaving via tailscale0. That path is
#     governed by the Tailscale ACLs instead (docs/tailscale-acl.md, SEC-11).
#     Do not "fix" this by inserting the jump at position 1: netavark and
#     tailscale both re-insert their own jumps at the head on restart, so the
#     ordering would not hold anyway.
#   - IPv4 only, on purpose: hyper has no global IPv6 address and no IPv6 route
#     besides tailscale0, so there is no v6 path between the two segments. If
#     IPv6 is ever enabled on these VLANs, this needs an ip6tables twin.
{
  flake.modules.nixos.hyper =
    { config, ... }:
    let
      inherit (config.constants.hosts.hyper) lanNetwork;
      bridge = "br-iot";
      chain = "iot-forward";

      # Not constants: these belong to the modules that create them, and are
      # repeated here only because iptables needs literals.
      podmanNetwork = "10.88.0.0/16"; # podman0, see medias/immich.nix
      vpnVeth = "10.200.0.0/30"; # veth-vpn-host, see downloads/vpn.nix
    in
    {
      networking.firewall = {
        # An own chain, rebuilt from scratch on every firewall start: the unit
        # does not flush FORWARD (NixOS does not manage it), so appending rules
        # directly would stack a duplicate set on every `nh os switch`.
        extraCommands = ''
          iptables -N ${chain} 2>/dev/null || true
          iptables -F ${chain}

          # Replies to connections opened from the trusted side: allowed. This
          # is what keeps LAN -> IoT and host -> IoT working in both directions.
          iptables -A ${chain} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

          # New connections from the IoT segment into anything internal: dropped
          # silently (DROP, not REJECT — an untrusted segment gets no feedback).
          iptables -A ${chain} -d ${lanNetwork} -j DROP
          iptables -A ${chain} -d ${podmanNetwork} -j DROP
          iptables -A ${chain} -d ${vpnVeth} -j DROP

          # Everything else falls back to the FORWARD policy untouched: this
          # closes lateral movement, it does not touch egress. No IoT device
          # uses hyper as its gateway today (the FORWARD counters were flat),
          # but breaking one silently is not worth the extra reach.
          iptables -A ${chain} -j RETURN

          iptables -C FORWARD -i ${bridge} -j ${chain} 2>/dev/null \
            || iptables -A FORWARD -i ${bridge} -j ${chain}
        '';

        extraStopCommands = ''
          iptables -D FORWARD -i ${bridge} -j ${chain} 2>/dev/null || true
          iptables -F ${chain} 2>/dev/null || true
          iptables -X ${chain} 2>/dev/null || true
        '';
      };
    };
}
