{ username, ... }:
{
  services.backups.enable = true;
  services.backups.configurations.laptop = {
    source_directories = [
      "/home/${username}/.config/sops"
      "/home/${username}/.config/incus"
      "/home/${username}/.config/Yubico"
      "/home/${username}/.gnupg"
      "/home/${username}/.password-store"
      "/home/${username}/Dev"
      "/home/${username}/Documents"
      "/home/${username}/Nixos"
    ];
  };
}
