{
  inputs,
  ...
}:
let
  flake.modules.darwin.m4.imports = with inputs.self.modules.darwin; [
    common
    logikdev
  ];

in
{
  inherit flake;
}
