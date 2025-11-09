{

  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.nodejs_20 ];
    };

}
