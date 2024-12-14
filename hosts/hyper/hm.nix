{ ... }:
{

  programs = {
    zsh.enable = true;
    zsh.loginExtra = "gpgconf --launch gpg-agent";
  };

}
