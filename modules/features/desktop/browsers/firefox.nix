{ inputs, lib, ... }:
let
  inherit (inputs.self.meta.owner) domain;

  k8s = app: "https://${app}.k8s.${domain}";
  hyper = app: "https://${app}.hyper.${domain}";
  tail = app: "https://${app}.bream-toad.ts.net";

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
    "Jellyseerr" = tail "jellyseerr";
    "Jellyfin" = hyper "jellyfin";
    "Radarr" = k8s "radarr";
    "Sonarr" = k8s "sonarr";
    "Prowlarr" = k8s "prowlarr";
    "Torrent" = k8s "torrent";
  };

  infra = mkBookmarksFolder "Infra" {
    "Vaultwarden" = tail "vaultwarden";
    "Longhorn" = tail "longhorn";
    "Authentik" = k8s "authentik";
    "Minio" = hyper "minio";
    "Adguard" = hyper "dns";
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
    HomeAssistant = tail "hass";
    Immich = tail "immich";
    N8N = k8s "n8n";
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
