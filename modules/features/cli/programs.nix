{ inputs, ... }:
{

  flake.modules.homeManager.logikdev.imports = [ inputs.self.modules.homeManager.cli ];

  flake.modules.homeManager.cli =
    { pkgs, config, ... }:
    let
      linuxPackages = if pkgs.stdenv.isLinux then [ pkgs.wl-clipboard ] else [ ];
      os = if pkgs.stdenv.isLinux then "os" else "darwin";
      rebuildHyper = pkgs.writeShellScriptBin "nrt" ''
        ssh hyper -- 'nh os switch'
      '';
    in
    {
      home.packages = [
        pkgs.barman
        pkgs.brave
        pkgs.bat
        pkgs.dig
        pkgs.dust
        pkgs.btop
        pkgs.fd
        pkgs.ncdu
        pkgs.rage
        pkgs.ripgrep
        pkgs.sops
        pkgs.ttyper
        rebuildHyper
      ]
      ++ linuxPackages;

      programs.nh = {
        enable = true;
        clean.enable = true;
        homeFlake = config.constants.users.logikdev.flakeDir;
        osFlake = config.constants.users.logikdev.flakeDir;
      };

      programs.fzf = {
        enable = true;
        enableFishIntegration = true;
        defaultCommand = "fd --type f";
        changeDirWidgetCommand = "fd --type d";
        defaultOptions = [
          "--color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9 --color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9 --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6 --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4"
        ];
      };

      programs.starship = {
        enable = true;
        enableFishIntegration = true;
      };

      programs.eza = {
        enable = true;
        enableFishIntegration = true;
      };

      programs.yazi = {
        enable = true;
        enableFishIntegration = true;
        shellWrapperName = "y";
      };

      home.shellAliases = rec {
        cat = "bat";
        htop = "btop";
        nos = "nh ${os} switch";
        grep = "rg";
        ls = "eza -1 -l --icons=auto --group-directories-first";
        lsa = ls + " -a";
        ffp = ''fzf --preview "bat --color=always {}" --bind "enter:become(vim {1} + {2})" --border'';
      };
    };
}
