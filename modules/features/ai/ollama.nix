{ ... }:
{
  flake.modules.nixos.ollama =
    { pkgs, ... }:
    {
      # La P4000 est du Pascal (compute capability 6.1). Le défaut nixpkgs
      # (CUDA 12.9) compile pour sm_75+ uniquement → ne tournerait PAS sur ce
      # GPU (fallback CPU) et prend 1-2 h à compiler. On épingle 6.1 : build
      # mono-arche (rapide) et réellement accéléré sur la P4000.
      nixpkgs.config.cudaCapabilities = [ "6.1" ];

      services.ollama = {
        enable = true;
        # Accélération CUDA sur la Quadro P4000 (Pascal) via le paquet
        # ollama-cuda (CUDA embarqué) — pas besoin de cudaSupport global.
        # (l'ancienne option `acceleration` a été retirée de nixpkgs.)
        package = pkgs.ollama-cuda;

        # API locale uniquement. Les futurs consommateurs (Paperless-AI, n8n)
        # tourneront sur hyper ; leur connectivité conteneur → hôte sera câblée
        # au moment de les ajouter (host-gateway ou écoute sur le bridge).
        host = "127.0.0.1";
        port = 11434;

        # Modèles laissés sur le chemin par défaut (/var/lib/ollama/models,
        # géré par StateDirectory) : le service tourne en DynamicUser, un
        # chemin custom hors /var/lib casserait la propriété.
        loadModels = [
          "qwen3:8b" # extraction fine + JSON (thinking off) → Paperless-AI
          "gemma3:4b" # tri rapide en volume → mails n8n
        ];

        environmentVariables = {
          # VRAM partagée avec immich-ml (P4000, 8 Go) : un seul modèle chargé
          # à la fois, déchargé après 5 min d'inactivité pour rendre la VRAM.
          OLLAMA_MAX_LOADED_MODELS = "1";
          OLLAMA_KEEP_ALIVE = "5m";
        };
      };

      notify.services = [ "ollama" ];
    };
}
