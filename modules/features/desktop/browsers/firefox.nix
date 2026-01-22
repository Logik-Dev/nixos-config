{ inputs, lib, ... }:
let
  inherit (inputs.self.meta.owner) domain;

  hyper = app: "https://${app}.hyper.${domain}";

  mkBookmarksFolder = folder: bms: {
    name = folder;
    bookmarks = lib.mapAttrsToList (name: url: { inherit name url; }) bms;
  };

  separator = "separator";

  nixFolder = mkBookmarksFolder "Nix" {
    "Nixos Options" = "https://search.nixos.org/options";
    "HomeManager Options" = "https://nix-community.github.io/home-manager/options.xhtml";
    "Nixvim" = "https://nix-community.github.io/nixvim/index.html";
    "Dentritic" = "https://vic.github.io/dendrix/Dendritic.html";
    "Gaetan Lepage NixConfig" = "https://github.com/GaetanLepage/nix-config";
    "Flake-Parts" = "https://flake.parts";
    "NUR" = "https://nur.nix-community.org/";
  };

  seedbox = mkBookmarksFolder "Seedbox" {
    "Jellyseerr" = hyper "jellyseerr";
    "Jellyfin" = hyper "jellyfin";
    "Radarr" = hyper "radarr";
    "Sonarr" = hyper "sonarr";
    "Prowlarr" = hyper "prowlarr";
    "Torrent" = hyper "torrent";
    "Jackett" = hyper "jackett";
  };

  infra = mkBookmarksFolder "Infra" {
    "Vaultwarden" = hyper "vaultwarden";
    "Minio" = hyper "minio";
    "Adguard" = hyper "dns";
    "Traefik" = "${hyper "traefik"}/dashboard/";
    "Unifi" = hyper "unifi";
  };

  github = mkBookmarksFolder "Github" {
    "Logikdev" = "https://github.com/Logik-Dev";
    "Niki modules" = "https://github.com/niki-on-github/nixos-modules";
    "Niki K3S" = "https://github.com/niki-on-github/nixos-k3s";
  };

  blogs = mkBookmarksFolder "Blogs" {
    "Alice Ryhl" = "https://draft.ryhl.io/";
  };

  linux = mkBookmarksFolder "Linux" {
    "Systemd tmpfiles" = "https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html";
  };

  home = mkBookmarksFolder "Home" {
    HomeAssistant = hyper "hass";
    Immich = hyper "immich";
    N8N = hyper "n8n";
  };

  toolbar = {
    name = toolbar;
    toolbar = true;
    bookmarks = [
      nixFolder
      separator
      seedbox
      separator
      infra
      separator
      github
      separator
      blogs
      separator
      linux
      separator
      home
    ];
  };

in
{
  flake.modules.homeManager.browsers =
    { pkgs, ... }:
    {
      programs.firefox = {
        enable = true;

        profiles.logikdev = {
          bookmarks.force = true;
          bookmarks.settings = [ toolbar ];
          extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
            bitwarden
            tridactyl
          ];
          settings = {
            "extensions.autoDisableScopes" = 0; # auto enable extensions
          };
        };
      };
    };
}
