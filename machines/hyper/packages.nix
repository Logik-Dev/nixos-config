{
  inputs,
  pkgs,
  ...
}:
{
  # Packages and overlays
  nixpkgs.overlays = [
    (final: prev: {
      pushr = inputs.pushr.defaultPackage.${pkgs.system};
    })
  ];
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    fira-code-symbols
  ];
  programs.nano.enable = false;
  environment.systemPackages = with pkgs; [
    bat
    btrfs-progs
    curl
    dig
    eza
    fd
    git
    iproute2
    htop
    iptables
    jq
    libxslt
    pciutils
    pushr
    ripgrep
    talosctl
    tcpdump
    vim
    wget
  ];
}