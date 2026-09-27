{ lib, ... }:
let
  # Bleeding-edge overlay : nixpkgs épingle opencode avec deux derivations
  # fixed-output (src + node_modules en hash récursif), donc bumper revient à
  # recalculer un hash bun install. On prend plutôt l'artefact binaire officiel
  # publié par opencode (le même que le script `curl | bash`), ce qui rend le
  # maintien trivial : version + hashes ci-dessous.
  version = "1.18.32";

  assets = {
    aarch64-darwin = {
      file = "opencode-darwin-arm64.zip";
      hash = "sha256-+mQ/k0AcE1CNjVE3gOVM6cwBID1QERS+m4jWJAi4EB8=";
    };
    x86_64-darwin = {
      file = "opencode-darwin-x64.zip";
      hash = "sha256-okvxBJk4L4hV4Z0qCBuGg+SrmcfCr/sy3ImxfIoAzNY=";
    };
    x86_64-linux = {
      file = "opencode-linux-x64.tar.gz";
      hash = "sha256-MEbgQE/cYPuAMH56R4JLoHR3NkF4pNCbqoVISW3W1Ds=";
    };
    aarch64-linux = {
      file = "opencode-linux-arm64.tar.gz";
      hash = "sha256-VoRht9TYwZhlyX6aEQLmEwScYDnQH+dyFU3oc8GGWEA=";
    };
  };

  opencodeBin =
    pkgs:
    let
      asset =
        assets.${pkgs.stdenv.hostPlatform.system}
          or (throw "opencode: unsupported system ${pkgs.stdenv.hostPlatform.system}");
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
    in
    pkgs.stdenvNoCC.mkDerivation (_finalAttrs: {
      pname = "opencode";
      inherit version;

      src = pkgs.fetchurl {
        url = "https://github.com/anomalyco/opencode/releases/download/v${version}/${asset.file}";
        inherit (asset) hash;
      };

      nativeBuildInputs = [
        pkgs.makeBinaryWrapper
      ]
      ++ lib.optionals isDarwin [ pkgs.unzip ]
      # `codesign` a besoin de codesign_allocate.
      ++ lib.optionals isDarwin [ pkgs.darwin.sigtool ];

      dontConfigure = true;
      dontBuild = true;

      unpackPhase = ''
        runHook preUnpack
        mkdir -p source
        ${if isDarwin then "unzip -q \"$src\" -d source" else "tar -xzf \"$src\" -C source"}
        runHook postUnpack
      '';

      installPhase = ''
        runHook preInstall
        install -Dm755 "$NIX_BUILD_TOP/source/opencode" $out/bin/opencode
        wrapProgram $out/bin/opencode \
          --prefix PATH : ${lib.makeBinPath ([ pkgs.ripgrep ] ++ lib.optionals isDarwin [ pkgs.sysctl ])} \
          --set OPENCODE_DISABLE_AUTOUPDATE true
        runHook postInstall
      '';

      # Le wrapping invalide la signature ; on resigne l'exécutable en ad-hoc.
      # `sign` (signingUtils) renseigne CODESIGN_ALLOCATE, requis par le
      # `codesign` de sigtool.
      postInstall = lib.optionalString isDarwin ''
        source ${pkgs.darwin.signingUtils}
        sign $out/bin/.opencode-wrapped
      '';

      dontStrip = true;

      meta = {
        description = "AI coding agent built for the terminal";
        homepage = "https://github.com/anomalyco/opencode";
        changelog = "https://github.com/anomalyco/opencode/releases/tag/v${version}";
        license = lib.licenses.mit;
        mainProgram = "opencode";
        sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
        platforms = builtins.attrNames assets;
      };
    });

  overlay = final: _prev: {
    opencode = opencodeBin final;
  };

  # Injecte l'overlay au niveau système (nixos + darwin), cf. dev/jj.nix.
  # `programs.opencode.package` récupère ainsi `pkgs.opencode` overridé.
  applyOverlay = {
    nixpkgs.overlays = [ overlay ];
  };
in
{
  flake.modules = {
    nixos.common.imports = [ applyOverlay ];
    darwin.common.imports = [ applyOverlay ];

    homeManager.opencode =
      { lib, pkgs, ... }:
      {
        programs.opencode = {
          enable = true;
          package = pkgs.opencode;

          settings = {
            # Modèle par défaut (build) : DeepSeek V4.1 Flash.
            # Cache-hit à $0.003/M (50x moins cher que l'input frais) =
            # imbattable pour un agent qui relit son contexte en boucle
            # (93% de cache-hit constaté). Variante "high" par défaut ;
            # passer sur "max" au cas par cas (tâche bloquante).
            model = "opencode-go/deepseek-v4.1-flash";

            # Modèle "small" (titres de session + résumés) : gratuit sur Zen.
            # Les données peuvent servir à l'amélioration du modèle — OK pour
            # des titres.
            small_model = "opencode/mimo-v2.6-flash-free";

            # Hygiène de contexte : plafonne les sorties d'outils volumineuses
            # pour limiter l'input frais (facturé 50x le cache-hit).
            tool_output = {
              max_lines = 300;
              max_bytes = 16384;
            };

            # Compaction auto : évite les sessions à plusieurs millions de
            # tokens (médiane constatée : 266K, moyenne : 7,9M).
            compaction = {
              auto = true;
              tail_turns = 12;
            };

            # Pas de partage public des sessions.
            share = "disabled";

            agent = {
              # PLAN : même modèle que build, effort "high" par défaut.
              plan = {
                model = "opencode-go/deepseek-v4.1-flash";
                variant = "high";
              };

              # BUILD : écriture du code + boucle de correction clippy/tests.
              build = {
                model = "opencode-go/deepseek-v4.1-flash";
                variant = "high";
              };

              # EXPLORE (built-in) : lecture/recherche en sous-agent, cheap.
              explore = {
                model = "opencode-go/mimo-v2.6-flash";
                variant = "low";
              };

              # SCOUT : sous-agent de recherche / lecture de code, sans édition.
              # Modèle ultra bon marché pour préserver la marge des limites 5h.
              scout = {
                description = "Recherche et lecture de code, repérage. Aucune édition.";
                mode = "subagent";
                model = "opencode-go/mimo-v2.6-flash";
                variant = "low";
                tools = {
                  write = false;
                  edit = false;
                };
              };
            };

            # Garde-fous : le commit reste sous contrôle humain.
            # L'agent PROPOSE le message conventionnel (cf. AGENTS.md), il ne
            # committe pas. OpenCode applique la dernière règle qui matche, donc
            # le catch-all "*" doit précéder les règles spécifiques (DAG).
            permission = {
              edit = "allow";
              bash = {
                "*" = lib.hm.dag.entryBefore [
                  "jj describe*"
                  "jj commit*"
                  "jj squash*"
                  "git commit*"
                  "git push*"
                  "rm *"
                ] "allow";
                "jj describe*" = "ask";
                "jj commit*" = "ask";
                "jj squash*" = "ask";
                "git commit*" = "ask";
                "git push*" = "ask";
                "rm *" = "ask";
              };
            };
          };
        };
      };
  };
}
