{ inputs, ... }:
let
  flake.modules.nixos.common.imports = [
    linux
    agenix
  ];

  flake.modules.darwin.common.imports = [
    darwin
    agenix
  ];

  hostKeys = {
    hyper = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK2VcspYbzVcMN9I1QjbhEErS52gfrp5rXNPBfG3YvNi";
    m4 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGuugxcVZbtbO6d/6glN4/ptUF0FcqsJlqaptm/+GQcn";
    sonicmaster = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIKWq7Zig25N+JdghtVp/T4V1gr1VKNG9egaQjWU4adb";
  };

  yubikeyIdentity = "${inputs.self}/secrets/age-yubikey-identity.identity";

  linux =
    { config, lib, ... }:
    {
      imports = [
        inputs.agenix.nixosModules.default
        inputs.agenix-rekey.nixosModules.default
      ];

      # agenix only derives identityPaths from services.openssh.hostKeys when
      # sshd is enabled; hosts without sshd (sonicmaster) still get their host
      # keys generated (sshd-keygen is independent of enable) and need them to
      # decrypt their secrets.
      age.identityPaths = map (e: e.path) (
        lib.filter (e: e.type == "rsa" || e.type == "ed25519") config.services.openssh.hostKeys
      );
    };

  darwin = {
    imports = [
      inputs.agenix.darwinModules.default
      inputs.agenix-rekey.darwinModules.default
    ];
  };

  agenix =
    { config, ... }:
    {
      age.rekey = {
        storageMode = "local";
        hostPubkey = hostKeys.${config.networking.hostName};
        localStorageDir = inputs.self.outPath + "/secrets/rekeyed/${config.networking.hostName}";
        masterIdentities = [
          yubikeyIdentity
          {
            # Software fallback identity, m4-local: rekeying happens on the
            # Mac (the YubiKey plugin identity above is the primary).
            pubkey = "age12cd6wdnk3su0wkedg7lm5uvcg79hqw28yp6e3h6y944wcaj94cgs53w43h";
            identity = "/Users/logikdev/.config/age/keys.txt";
          }
        ];

      };
    };

in
{
  inherit flake;
}
