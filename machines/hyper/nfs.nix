{ ... }:
{
  # Enable NFS server
  services.nfs.server = {
    enable = true;
    exports = ''
      # Export medias directory to kubernetes
      /mnt/storage/medias 10.0.100.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=991)

      # Export archives directory to kubernetes
      /mnt/storage/archives 10.0.100.0/24(rw,sync,no_subtree_check,no_root_squash)

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
}
