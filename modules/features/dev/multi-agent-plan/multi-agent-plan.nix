{ inputs, ... }:
{
  # Orchestrateur de planification multi-agents :
  # Claude planifie (lecture seule), OpenCode et Claude relisent, OpenCode
  # fusionne en plan atomique, puis exécute chaque étape dans une TUI avec un
  # commit atomique par étape sous supervision humaine.
  #
  # Usage : multi-agent-plan --repo ~/projet --task "..." --test-cmd "nix flake check"
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
