{ inputs, ... }:
let

  flake.modules.homeManager.common.imports = [
    gpg
  ];

  gpg = {
    programs.gpg = {
      enable = true;
      publicKeys = [
        {
          text = builtins.readFile (inputs.self + "/secrets/gpg.pub");
          trust = 5;
        }
      ];
    };

    services.gpg-agent = {
      enable = true;
      enableFishIntegration = true;
      enableSshSupport = true;
      enableScDaemon = true;
    };

  };

in

{
  inherit flake;

}
