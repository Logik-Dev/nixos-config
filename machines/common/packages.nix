{ pkgs, inputs, ... }:
{
  # add pushr notifier for pushover to nixpkgs
  nixpkgs.overlays = [
    (final: prev: {
      pushr = inputs.pushr.defaultPackage.${pkgs.system};
    })
  ];
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    fira-code-symbols
  ];
  environment.systemPackages = with pkgs; [
    bat
    borgbackup
    btrfs-progs
    curl
    dig
    eza
    fd
    git
    htop
    pushr
    ripgrep
    vim
    wget
  ];

  environment.shellAliases = {
    cat = "bat";
    l = "eza";
    ll = "eza -l";
    ls = "eza -l";
    llt = "eza -lT";
    tf = "noglob tofu";
    tfp = "noglob tofu plan";
    tfa = "noglob tofu apply";
    tfat = "noglob tofu apply --target=";
    g = "git";
    ga = "git add";
    gs = "git status";
    gcm = "git commit -m";
    gcam = "git commit --amend --no-edit";
    gcb = "git checkout -b";

  };

}
