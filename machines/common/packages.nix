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
    borgbackup
    btrfs-progs
    curl
    dig
    fd
    git
    htop
    pushr
    ripgrep
    vim
    wget
  ];

}
