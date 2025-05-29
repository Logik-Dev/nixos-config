{ pkgs, inputs, ... }:
{
  # add pushr notifier for pushover to nixpkgs
  nixpkgs.overlays = [
    (final: prev: {
      pushr = inputs.pushr.defaultPackage.${pkgs.system};
    })
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
