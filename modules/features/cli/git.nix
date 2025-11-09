{ inputs, ... }:
let

  inherit (inputs.self.meta.owner) fullname email gpg;

  flake.modules.nixos.sonicmaster =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.claude-code ];
    };

  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      programs.git = {
        enable = true;
        signing.key = gpg;
        signing.signByDefault = true;
        settings.user.email = email;
      };

      home.packages = [
        (pkgs.rustPlatform.buildRustPackage rec {
          pname = "starship-jj";
          version = "0.7.0";

          src = pkgs.fetchCrate {
            inherit pname version;
            hash = "sha256-oisz3V3UDHvmvbA7+t5j7waN9NykMUWGOpEB5EkmYew=";
          };

          cargoHash = "sha256-NNeovW27YSK/fO2DjAsJqBvebd43usCw7ni47cgTth8=";

          meta = with pkgs.lib; {
            description = "Starship plugin for jj (Jujutsu VCS)";
            homepage = "https://gitlab.com/lanastara_foss/starship-jj";
            license = licenses.mit;
            maintainers = [ ];
          };
        })
      ];

      programs.jujutsu = {
        enable = true;
        settings = {
          user = {
            inherit email;
            name = fullname;
          };
          inherit email;
          signing.behavior = "own";
          signing.backend = "gpg";
          signing.key = gpg;

        };
      };

      programs.starship.settings = {
        custom.jj = {
          command = "prompt";
          format = "$output";
          ignore_timeout = true;
          shell = [
            "starship-jj"
            "--ignore-working-copy"
            "starship"
          ];
          use_stdin = false;
          when = true;
        };

        format = "$all\${custom.jj}$character";
      };
    };
in
{
  inherit flake;
}
