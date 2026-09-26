{ app }:
{ lib, ... }:
{
  # Shared filesystem hygiene for the *arr/media services: group-writable so
  # qBittorrent, the *arr stack and the media players can cooperate on the
  # same files under /mnt/storage and /mnt/ultra.
  systemd.services.${app}.serviceConfig.UMask = lib.mkForce "0002";
  services.${app}.group = "media";
}
