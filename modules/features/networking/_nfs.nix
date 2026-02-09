{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) username;

  flake.modules.nixos.hyper.imports = [ nfsServer ];
  flake.modules.nixos.sonicmaster.imports = [ nfsClient ];

  nfsServer = {
    services.nfs.server = {
      enable = true;
      exports = ''
        /mnt/storage/medias 10.0.100.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=991) 192.168.10.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=991)
        /mnt/storage/archives 192.168.10.0/24(rw,sync,no_subtree_check,no_root_squash)
      '';
    };

    # Configure NFSv4 only (disable older versions)
    services.nfs.settings = {
      nfsd.vers3 = false;
      nfsd.vers4 = true;
      nfsd."vers4.2" = true;
    };

    # Enable required services for NFS
    services.rpcbind.enable = true;
  };

  nfsClient = {
    boot.supportedFilesystems = [ "nfs" ];
    fileSystems."/home/${username}/Medias" = {
      device = "192.168.10.100:/mnt/storage/medias";
      fsType = "nfs";
      options = [
        "nfsvers=4.2"
        "x-systemd.automount"
        "x-systemd.idle-timeout=600"
        "noauto"
      ];
    };
  };

in
{
  inherit flake;
}
