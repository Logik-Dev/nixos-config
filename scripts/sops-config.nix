{ pkgs, lib, ... }:
let
  inherit (builtins)
    filter
    readFile
    readDir
    attrNames
    map
    elemAt
    ;

  # utils
  lines = filename: lib.strings.splitString "\n" (readFile filename);
  firstLine = filename: elemAt (lines filename) 0;

  # common keys: yubikey and rescue
  pgp = [ "F5A34D392D22853E7EB1FA85AC259B4007CB7CE9" ];
  rescue = firstLine ../machines/sonicmaster/keys/rescue.pub;
  sonicmaster = firstLine ../machines/sonicmaster/keys/age.pub;

  # all machines names
  machines = filter (m: m != "common") (attrNames (readDir ../machines));

  # all machines age.pub
  allKeys = map (name: firstLine ../machines/${name}/keys/age.pub) machines;

  # generate a rule block with at least pgp and rescue keys
  mkRuleWithKeys = machine: keys: {
    path_regex = "(\\.)?${machine}\\.*";
    key_groups = [
      {
        inherit pgp;
        age = [ rescue ] ++ keys;
      }
    ];
  };

  # generate rule block for a specific machine
  mkRule = machine: mkRuleWithKeys machine [ (firstLine ../machines/${machine}/keys/age.pub) ];

  sopsConfig = {

    creation_rules = [
      # special rules
      (mkRuleWithKeys "common" allKeys)
      (mkRuleWithKeys "special_args" [ ])
      (mkRuleWithKeys "opentofu" [ sonicmaster ])

      # machines rules
    ] ++ map mkRule machines;
  };
in
pkgs.writeText "sops.yaml" (lib.generators.toYAML { } sopsConfig)
