{ username, ... }:
{
  # Enable NFS server
  services.nfs.server = {
    enable = true;
    exports = ''
      # Export medias directory to entire 192.168.0.0/16 network
      /mnt/future/medias 192.168.0.0/16(rw,sync,no_subtree_check,no_root_squash
    '';
  };

  # Configure NFSv4 only (disable older versions)
  services.nfs.settings = {
    nfsd.vers3 = false;
    nfsd.vers4 = true;
    nfsd."vers4.2" = true;
  };

  # Ensure the medias directory exists and has proper permissions
  systemd.tmpfiles.settings = {
    "10-nfs-medias" = {
      "/mnt/future/medias" = {
        d = {
          group = "media";
          mode = "775";
          user = username;
        };
      };
    };
  };

  # Enable required services for NFS
  services.rpcbind.enable = true;
}

