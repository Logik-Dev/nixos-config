{
  inputs,
  ...
}:
let
  flake.modules.darwin.m4.imports =
    (with inputs.self.modules.darwin; [
      common
      hetznerStoragebox
      logikdev
      ollama
      tailscale
    ])
    ++ [ ];

in
{
  inherit flake;
}
