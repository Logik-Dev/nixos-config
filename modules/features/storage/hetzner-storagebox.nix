{ ... }:
let
  # Offsite restic target: Hetzner Storage Box (SFTP backend).
  #
  # The private key that unlocks the offsite backup lives encrypted in the repo
  # (agenix), NOT only on hyper — otherwise a dead hyper could not be restored
  # from its own offsite backup (chicken-and-egg). During a bare-metal restore
  # the key is re-materialised from the master identity (age key / Yubikey),
  # exactly like restic.env.
  #
  # The actual repository URL (sftp:uXXXXXX@uXXXXXX.your-storagebox.de:) is set
  # in modules/features/storage/restic.nix (default `defaultRepositories`).

  # Pinned host key of the Storage Box (ssh-keyscan -p 23, fingerprint
  # SHA256:XqONwb1S0zuj5A1CDxpOSuD2hnAArV1A3wKY7Z3sdgM).
  knownHost = {
    hostNames = [ "[u625917.your-storagebox.de]:23" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
  };

  # System-wide SSH client config so BOTH the restic backup services and the
  # restic-exporter (which only sees RESTIC_REPOSITORY, with no per-repo
  # options) resolve the right port/key/known-hosts without depending on
  # $HOME (the exporter runs with ProtectHome=true). The user comes from the
  # sftp:user@host URL, so it is not hardcoded here.
  sshExtraConfig = config: ''
    Host *.your-storagebox.de
      Port 23
      IdentityFile ${config.age.secrets."hetzner-storagebox".path}
      IdentitiesOnly yes
      StrictHostKeyChecking yes
      UserKnownHostsFile /etc/ssh/ssh_known_hosts

    Host storagebox
      HostName u625917.your-storagebox.de
      User u625917
      Port 23
      IdentityFile ${config.age.secrets."hetzner-storagebox".path}
      IdentitiesOnly yes
      StrictHostKeyChecking yes
      UserKnownHostsFile /etc/ssh/ssh_known_hosts
  '';
in
{
  flake.modules.nixos.hetznerStoragebox =
    { config, ... }:
    {
      # The secret itself is auto-discovered from secrets/hosts/hyper/*.age by
      # modules/features/security/secrets.nix (default owner root / mode 0400,
      # read by the root-run restic services) — no explicit declaration needed.
      programs.ssh.extraConfig = sshExtraConfig config;
      programs.ssh.knownHosts.hetzner-storagebox = knownHost;
    };

  flake.modules.darwin.hetznerStoragebox =
    { config, ... }:
    {
      # On m4 the secret is auto-discovered from secrets/hosts/m4/*.age; override
      # the owner so the user can read the private key for interactive SSH.
      age.secrets."hetzner-storagebox".owner = "logikdev";
      programs.ssh.extraConfig = sshExtraConfig config;
      programs.ssh.knownHosts.hetzner-storagebox = knownHost;
    };
}
