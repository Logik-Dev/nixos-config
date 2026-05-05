{ ... }:

{
  flake.modules.homeManager.common =
    {
      pkgs,
      lib,
      ...
    }:
    {

      home.activation = lib.mkIf pkgs.stdenv.isDarwin {
        aliasApplications = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          app_folder="$HOME/Applications/Home Manager Apps"
          echo "Setting up $app_folder..." >&2

          # Nettoyer complètement (même les backups)
          rm -rf "$app_folder" "$app_folder.bak"
          mkdir -p "$app_folder"

          # Chercher les apps dans la nouvelle génération
          if [ -d "$newGenPath/home-path/Applications" ]; then
            app_count=0
            for app in "$newGenPath/home-path/Applications"/*.app; do
              if [ -e "$app" ]; then
                app_name=$(basename "$app")
                echo "  → $app_name" >&2
                ${pkgs.mkalias}/bin/mkalias "$app" "$app_folder/$app_name"
                app_count=$((app_count + 1))
              fi
            done
            
            if [ $app_count -gt 0 ]; then
              echo "  Linked $app_count application(s)" >&2
              # Réindexer pour Spotlight
              $DRY_RUN_CMD mdimport "$app_folder" 2>/dev/null || true
            fi
          fi
        '';
      };
    };

  flake.modules.darwin.common =
    {
      pkgs,
      lib,
      ...
    }:
    {
      environment.systemPackages = [
        pkgs.mkalias
        pkgs.neovim
        pkgs.nixd
        pkgs.nixfmt
      ];

      system.activationScripts.applications.text = lib.mkForce ''
        echo "Setting up /Applications/Nix Apps..." >&2
        app_folder="$HOME/Applications/Nix Apps"

        # Nettoyer et recréer
        rm -rf "$app_folder"
        mkdir -p "$app_folder"

        # Attendre que le système soit activé
        if [ -d "/run/current-system/sw/Applications" ]; then
          app_count=0
          for app in /run/current-system/sw/Applications/*.app; do
            if [ -e "$app" ]; then
              app_name=$(basename "$app")
              echo "  → $app_name" >&2
              ${pkgs.mkalias}/bin/mkalias "$app" "$app_folder/$app_name"
              app_count=$((app_count + 1))
            fi
          done
          
          if [ $app_count -eq 0 ]; then
            echo "  No applications found" >&2
          else
            echo "  Linked $app_count application(s)" >&2
            # Forcer Spotlight à réindexer
            mdimport "$app_folder" 2>/dev/null || true
          fi
        else
          echo "  System not yet activated, will link apps on next activation" >&2
        fi
      '';
    };
}
