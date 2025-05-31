{ pkgs, ... }:
{

  environment.systemPackages = [
    pkgs.jellyfin
    pkgs.jellyfin-web
    pkgs.jellyfin-ffmpeg
  ];

  # Jellyfin
  services.jellyfin.enable = true;
  services.jellyfin.group = "media";

  # skip intro plugin fix
  nixpkgs.overlays = [
    (final: prev: {
      jellyfin-web = prev.jellyfin-web.overrideAttrs (
        finalAttrs: previousAttrs: {
          installPhase = ''
            runHook preInstall

            # this is the important line
            sed -i "s#</head>#<script src=\"configurationpage?name=skip-intro-button.js\"></script></head>#" dist/index.html

            mkdir -p $out/share
            cp -a dist $out/share/jellyfin-web

            runHook postInstall
          '';
        }
      );
    })
  ];
}
