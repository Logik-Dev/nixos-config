{ inputs, ... }:
{
  # Orchestrateur de planification multi-agents :
  # sans --task/--task-file, une session OpenCode interactive précise le plan
  # (capturé ensuite via la base locale) ; avec, OpenCode planifie en headless
  # (--plan-with claude pour Claude). OpenCode et Claude relisent, OpenCode
  # fusionne en plan atomique, puis exécute chaque étape dans une TUI avec un
  # commit atomique par étape sous supervision humaine.
  #
  # Profils : --profile fast|balanced|max (défaut : balanced) fixe les défauts
  # (moteur du plan, effort Claude, context pack, budget) ; un flag explicite
  # l'emporte sur le profil, lui-même prioritaire sur le défaut intégré.
  #
  # Usage : multi-agent-plan --repo ~/projet --test-cmd "nix flake check"
  #         multi-agent-plan --repo ~/projet --task "..." --profile max
  # Les prompts sont versionnés dans ./prompts et surchargeables par --prompt-dir.
  perSystem =
    { pkgs, ... }:
    {
      packages.multi-agent-plan = pkgs.writeShellApplication {
        name = "multi-agent-plan";
        runtimeInputs = [ pkgs.python3 ];
        text = ''
          export MULTI_AGENT_PLAN_PROMPTS=${./prompts}
          exec python3 ${./orchestrator.py} "$@"
        '';
      };

      # Sans garde de système : le harnais existe aussi sur x86_64-linux.
      # git est requis par les tests de head_commit/commit_count (dépôt
      # temporaire réel), absent du PATH de build sinon.
      checks.multi-agent-plan =
        pkgs.runCommand "multi-agent-plan-tests"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.git
            ];
          }
          ''
            cp ${./orchestrator.py} orchestrator.py
            cp -r ${./prompts} prompts
            python3 -m unittest discover ${./tests}
            touch $out
          '';
    };

  # Installé uniquement là où Claude Code est activé (m4), car l'outil
  # nécessite les deux CLI claude et opencode dans le PATH.
  flake.modules.homeManager.multi-agent-plan =
    { pkgs, ... }:
    {
      home.packages = [
        inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.multi-agent-plan
      ];
    };
}
