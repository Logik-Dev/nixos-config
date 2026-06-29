{
  flake.modules = {
    darwin.common = {
      environment.variables = {
        EDITOR = "nvim";
      };
    };
    homeManager.common = { pkgs, ... }: {
      home.sessionVariables = {
        EDITOR = "nvim";
        LAB = "$HOME/Homelab";
        FLAKE = "$HOME/Homelab/Nixos";
        SECRETSPEC_PROVIDER = if pkgs.stdenv.hostPlatform.isDarwin then "keyring" else "dotenv";
        #SSH_AUTH_SOCK = "$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
      };
    };
  };
}
