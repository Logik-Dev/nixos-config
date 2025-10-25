{
  flake.modules.homeManager.virtualization =
    { pkgs, ... }:
    {
      programs.k9s.enable = true;
      home.packages = [
        pkgs.fluxcd
        pkgs.kubectl
      ];
    };
}
