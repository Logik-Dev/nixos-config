# Permet à un module de déclarer ses automatisations Home Assistant à côté du
# service qu'elles pilotent, plutôt que dans un YAML géant édité à l'UI.
#
# Le rendu passe par la clé `automation nix:`, distincte de `automation:`
# (`!include automations.yaml`) que l'UI écrit et qui reste mutable. HA fusionne
# les deux : `cv.domain_key` découpe la clé sur le premier espace et
# `extract_domain_configs` collecte **toutes** les clés du domaine (vérifié dans
# la source 2026.8.3). On peut donc déclarer sans rien retirer à l'UI.
#
# Le but n'est pas de tout déclarer — les automatisations bricolées à l'UI ont
# leur place dans le fichier mutable. C'est de rapprocher du dépôt celles qui
# pilotent un service que le dépôt déclare déjà.
_:
let
  automationsModule =
    { lib, config, ... }:
    {
      options.homeAssistant.automations = lib.mkOption {
        description = "Automatisations Home Assistant déclarées en nix, indexées par leur `id`.";
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        default = { };
      };

      config = lib.mkIf (config.homeAssistant.automations != { }) {
        services.home-assistant.config."automation nix" = lib.mapAttrsToList (
          id: body: { inherit id; } // body
        ) config.homeAssistant.automations;
      };
    };
in
{
  flake.modules.nixos.home-assistant.imports = [ automationsModule ];
}
