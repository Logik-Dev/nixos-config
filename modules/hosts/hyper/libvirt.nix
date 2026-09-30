{
  flake.modules.nixos.hyper =
    { config, ... }:
    {
      # La route `hass` vers la VM a été retirée le 2026-09-30 : la VM est
      # arrêtée et l'endpoint public renvoyait 502. Home Assistant est servi par
      # `ha.hyper.logikdev.fr` (features/home/home-assistant.nix).
      #
      # `libvirtd` reste actif et le domaine reste **défini mais arrêté** : le
      # qcow2 est le plan de repli, conservé au moins un mois (lot D du dossier).
      # Pour revenir en arrière il faudrait redéclarer cette route, démarrer le
      # domaine, et surtout **retirer l'intégration MQTT du natif d'abord** —
      # deux HA sur le même courtier commanderaient tout deux fois.
      users.users.${config.constants.users.logikdev.username}.extraGroups = [ "libvirtd" ];
      virtualisation.libvirtd.enable = true;
    };
}
