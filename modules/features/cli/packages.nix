{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        agenix-cli
        barman
        bat
        dig
        btop
        fd
        ripgrep
        sops
        wl-clipboard
      ];

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
      };

      home.shellAliases = rec {
        cat = "bat";
        htop = "btop";
        nrt = "sudo nixos-rebuild switch --flake .#hyper --build-host logikdev@192.168.10.100 --target-host logikdev@192.168.10.100 --use-remote-sudo";
        nos = "nh os switch";
        grep = "rg";
        ls = "eza -1 -l --icons=auto --group-directories-first";
        lsa = ls + " -a";
        ffp = ''fzf --preview "bat --color=always {}" --bind "enter:become(vim {1} + {2})" --border'';
      };
    };
}
