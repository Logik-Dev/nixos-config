{
  flake.modules = {
    darwin.common = {
      environment.variables = {
        EDITOR = "nvim";
      };
    };
    homeManager.common = {
      home.sessionVariables = {
        EDITOR = "nvim";
        LAB = "$HOME/Homelab";
        FLAKE = "$HOME/Homelab/Nixos";
        SSH_AUTH_SOCK = "$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
      };
    };
  };
}
