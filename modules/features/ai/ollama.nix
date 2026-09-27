_: {
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
          "gemma4:e4b"
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

  # macOS (M4 Pro, 24 Go) : nix-darwin n'a pas de `services.ollama`. On déclare
  # donc le binaire (store, Metal embarqué sur Apple Silicon — pas de CUDA à
  # gérer) + un agent launchd « user » maison. User agent obligatoire : Metal
  # requiert la session graphique, un daemon système n'y accède pas.
  #
  # Rôle : booster batch pour le tri de mails n8n (modèle plus gros = meilleur
  # suivi d'instructions que la P4000/8 Go). Pas de 24/7 attendu : les gros lots
  # tournent Mac réveillé. Le poids du modèle (qwen3:14b, ~9 Go) reste du state
  # → `ollama pull qwen3:14b` une fois (aucune approche ne le met dans le store).
  flake.modules.darwin.ollama =
    { config, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ollama ];

      launchd.user.agents.ollama.serviceConfig = {
        ProgramArguments = [
          "${pkgs.ollama}/bin/ollama"
          "serve"
        ];
        # KeepAlive : au login Tailscale n'a pas encore assigné l'IP → le bind
        # échoue une fois, launchd relance jusqu'à ce que l'IP existe.
        KeepAlive = true;
        RunAtLoad = true;
        EnvironmentVariables = {
          # N'écoute que sur l'IP Tailscale du Mac : joignable par n8n/hyper via
          # le tailnet, jamais exposé sur le wifi public (Ollama n'a pas d'auth).
          OLLAMA_HOST = "${config.constants.hosts.m4.tailscaleIp}:11434";
          OLLAMA_KEEP_ALIVE = "5m";
        };
        StandardOutPath = "/tmp/ollama.log";
        StandardErrorPath = "/tmp/ollama.err.log";
      };
    };
}
