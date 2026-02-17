{
  flake.modules.homeManager = {
    ai-agent = {
      programs.claude-code.enable = true;
    };

    ollama = {
      services.ollama.enable = true;
    };

  };
}
