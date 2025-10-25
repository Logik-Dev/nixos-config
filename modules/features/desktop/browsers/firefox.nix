{ inputs, lib, ... }:
let
  inherit (inputs.self.meta.owner) domain;

  k8sp = app: "https://${app}.k8sp.${domain}";
  hyper = app: "https://${app}.hyper.${domain}";
  tail = app: "https://${app}-prod.bream-toad.ts.net";

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
    "Torrent" = k8sp "torrent";
  };

  infra = mkBookmarksFolder "Infra" {
    "Vaultwarden" = hyper "vaultwarden";
    "Longhorn" = tail "longhorn";
    "Authentik" = k8sp "authentik";
    "Minio" = hyper "minio";
    "Adguard" = hyper "dns";
  };

  github = mkBookmarksFolder "Github" {
    "Logikdev" = "https://github.com/Logik-Dev";
  };

  blogs = mkBookmarksFolder "Blogs" {
    "Alice Ryhl" = "https://draft.ryhl.io/";
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
