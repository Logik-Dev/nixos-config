{ ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autocd = true;
    autosuggestion.enable = true;
    loginExtra = "gpgconf --launch gpg-agent";
  };

  programs.zsh.antidote = {
    enable = true;
    plugins = [
      "jeffreytse/zsh-vi-mode"
    ];
  };
}
