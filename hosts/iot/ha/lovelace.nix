{ ... }:
{
  services.home-assistant.lovelaceConfig = {
    title = "My Nix Home";
    views = [
      {
        path = "default_view";
        title = "My Nix Home";
        type = "masonry";
        cards = [

          {
            title = "FireTV Salon";
            theme = "happy";
            type = "custom:android-tv-card";
            remote_id = "remote.fire_tv_salon";
            media_player_id = "media_player.fire_tv_salon";
            rows = [
              [ "power" ]
              [
                "netflix"
                "disney"
                "primevideo"
                "youtube"
              ]
            ];
          }
          {
            name = "Sonos Playbar";
            type = "media-control";
            entity = "media_player.salon";
          }
          {
            name = "Jellyfin";
            theme = "sad";
            type = "media-control";
            entity = "media_player.stick_salon";
          }
        ];
      }
    ];
  };
}
