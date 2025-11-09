{ inputs, ... }:
let
  hostKeys = {
    hyper = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK2VcspYbzVcMN9I1QjbhEErS52gfrp5rXNPBfG3YvNi";
    sonicmaster = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIKWq7Zig25N+JdghtVp/T4V1gr1VKNG9egaQjWU4adb root@sonicmaster";
  };
in
{
  flake.modules.nixos.agenix =
    { config, ... }:
    {

      imports = [
        inputs.agenix.nixosModules.default
        inputs.agenix-rekey.nixosModules.default
      ];
      age.rekey = {
        masterIdentities = [ "${inputs.self}/secrets/age-yubikey-identity.pub" ];
        storageMode = "local";
        hostPubkey = hostKeys.${config.networking.hostName};
        localStorageDir = inputs.self + "/secrets/rekeyed/${config.networking.hostName}";
      };
    };
}
