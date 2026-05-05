{
  flake.modules.nixos.hyper = {
    networking.firewall.allowedTCPPorts = [
      3333
      11434
    ]; # rankode
    traefik.services.ollama.port = 11434;
  };

  flake.modules.homeManager = {
    ai-agent = {
      programs.claude-code.enable = true;

    };

    # ollama = {
    #   services.ollama = {
    #     enable = true;
    #     host = "0.0.0.0";
    #     port = 11434;
    #     acceleration = "cuda";
    #   };
    # };

  };
}
