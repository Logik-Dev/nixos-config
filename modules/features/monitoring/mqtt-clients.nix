# MON-11 — un client MQTT qui décroche doit être visible.
#
# L'angle mort qu'on a payé : `notify.services` surveille l'*unité* mosquitto,
# qui n'a jamais échoué, pendant que Home Assistant disparaissait du courtier
# pendant 2,5 jours (P0-9). Le courtier était vert, le service aussi, et tout
# le Zigbee était muet. Rien dans la supervision ne regardait les **clients**.
#
# Le signal est pris côté hôte, avec `ss` : pas de compte MQTT dédié, pas d'ACL
# `$SYS` à ouvrir, pas de mot de passe à faire circuler. Un client est identifié
# par son **unité systemd**, obtenue via pid → /proc/<pid>/cgroup — et pas par
# le nom de processus, qui ne discrimine rien ici : `ss` rapporte `MainThread`
# pour zigbee2mqtt et `.rankoder-wrapp` pour rankoder (vérifié).
#
# La liste des clients attendus est délibérément courte et explicite plutôt que
# déduite des connexions observées : c'est une *absence* qu'on veut détecter, et
# on ne détecte pas une absence à partir de ce qui est présent.
_: {
  flake.modules.nixos.mqtt-clients =
    { lib, pkgs, ... }:
    let
      # La VM Home Assistant (192.168.21.181) n'y est PAS, sciemment : elle est
      # décrochée depuis le 2026-09-27 (P0-9), c'est constaté et assumé, et elle
      # doit disparaître. L'y mettre créerait une alerte en échec permanent,
      # c'est-à-dire du bruit qu'on apprendrait à ignorer — exactement ce qui
      # rend une supervision inutile.
      #
      # `home-assistant.service` s'ajoute ici **au lot C**, quand l'instance
      # native prendra le courtier. C'est à ce moment que ce module vaudra le
      # plus : le même silence coûterait alors le même prix.
      expected = [
        "zigbee2mqtt.service"
        "rankoder.service"
      ];
    in
    {
      systemd.services.mqtt-monitor = {
        description = "Export connected MQTT client presence for Prometheus";
        path = with pkgs; [
          coreutils
          gnugrep
          iproute2
        ];
        serviceConfig = {
          Type = "oneshot";

          ProtectSystem = "strict";
          ReadWritePaths = [ "/var/lib/node-exporter-textfile" ];
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          # PrivateNetwork est volontairement absent : il faut voir les sockets
          # de l'hôte. AF_NETLINK parce que c'est par là que `ss` les lit.
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_NETLINK"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          MemoryDenyWriteExecute = true;
          LockPersonality = true;
          SystemCallArchitectures = "native";
          # Pas de ProtectProc : lire /proc/<pid>/cgroup des *autres* services
          # est précisément le mécanisme d'identification.
        };
        script = ''
          # `set +e` d'abord : NixOS préfixe son propre `set -e`, et un process
          # qui se termine entre le `ss` et la lecture de son /proc ne doit pas
          # tuer le relevé. Même raisonnement que vpn-monitor.
          set +e

          dir=/var/lib/node-exporter-textfile
          file="$dir/mqtt-clients.prom"
          umask 022

          expected=( ${lib.escapeShellArgs expected} )

          # Unités détenant une socket établie vers le courtier.
          connected=""
          for pid in $(ss -tnpH state established '( dport = :1883 )' 2>/dev/null \
                        | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u); do
            unit=$(grep -oE '[^/]+\.service' "/proc/$pid/cgroup" 2>/dev/null | head -1)
            [ -n "$unit" ] && connected="$connected $unit"
          done

          # Total côté serveur : compte aussi les clients *non* attendus, ce que
          # la jauge par client ne peut pas faire par construction.
          total=$(ss -tnH state established '( sport = :1883 )' 2>/dev/null | grep -c .)

          tmp="$file.tmp"
          {
            echo "# HELP mqtt_client_connected Whether an expected MQTT client currently holds a connection to the broker."
            echo "# TYPE mqtt_client_connected gauge"
            for unit in "''${expected[@]}"; do
              case " $connected " in
                *" $unit "*) v=1 ;;
                *) v=0 ;;
              esac
              echo "mqtt_client_connected{client=\"$unit\"} $v"
            done

            echo "# HELP mqtt_clients_total Established connections to the broker, expected or not."
            echo "# TYPE mqtt_clients_total gauge"
            echo "mqtt_clients_total ''${total:-0}"

            # Témoin de fraîcheur, même idiome que vpn_monitor_timestamp_seconds :
            # le collecteur textfile sert un .prom indéfiniment, donc un relevé
            # mort laisse des valeurs figées qui *paraissent* saines. Sans cet
            # horodatage, `absent()` ne se déclencherait jamais.
            echo "# HELP mqtt_monitor_timestamp_seconds Unix time of the last successful MQTT client survey."
            echo "# TYPE mqtt_monitor_timestamp_seconds gauge"
            echo "mqtt_monitor_timestamp_seconds $(date +%s)"
          } > "$tmp"
          mv -f "$tmp" "$file"
        '';
      };

      systemd.timers.mqtt-monitor = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*:0/2";
          RandomizedDelaySec = "20s";
          Persistent = true;
        };
      };

      # Met aussi l'unité dans l'`unit-include` de node_exporter (node.nix fait
      # l'union avec notify.services), donc un relevé en échec est lui-même
      # rattrapé par SystemdUnitFailed.
      notify.services = [ "mqtt-monitor" ];
    };
}
