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
  # The actual repository URL (sftp:user@host:) is set in
  # modules/features/storage/restic.nix (default `defaultRepositories`).

  # Pinned host keys of the Storage Box (ssh-keyscan -p 23; ed25519
  # fingerprint SHA256:XqONwb1S0zuj5A1CDxpOSuD2hnAArV1A3wKY7Z3sdgM). All three
  # key types are pinned, not just ed25519: pgBackRest reaches the box through
  # libssh2, which may negotiate a different host key type than OpenSSH would,
  # and then fails its known-hosts check against an ed25519-only pin.
  mkKnownHosts = host: {
    hetzner-storagebox = {
      hostNames = [ "[${host}]:23" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
    };
    hetzner-storagebox-rsa = {
      hostNames = [ "[${host}]:23" ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA5EB5p/5Hp3hGW1oHok+PIOH9Pbn7cnUiGmUEBrCVjnAw+HrKyN8bYVV0dIGllswYXwkG/+bgiBlE6IVIBAq+JwVWu1Sss3KarHY3OvFJUXZoZyRRg/Gc/+LRCE7lyKpwWQ70dbelGRyyJFH36eNv6ySXoUYtGkwlU5IVaHPApOxe4LHPZa/qhSRbPo2hwoh0orCtgejRebNtW5nlx00DNFgsvn8Svz2cIYLxsPVzKgUxs8Zxsxgn+Q/UvR7uq4AbAhyBMLxv7DjJ1pc7PJocuTno2Rw9uMZi1gkjbnmiOh6TTXIEWbnroyIhwc8555uto9melEUmWNQ+C+PwAK+MPw==";
    };
    hetzner-storagebox-ecdsa = {
      hostNames = [ "[${host}]:23" ];
      publicKey = "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAGK0po6usux4Qv2d8zKZN1dDvbWjxKkGsx7XwFdSUCnF19Q8psHEUWR7C/LtSQ5crU/g+tQVRBtSgoUcE8T+FWp5wBxKvWG2X9gD+s9/4zRmDeSJR77W6gSA/+hpOZoSE+4KgNdnbYSNtbZH/dN74EG7GLb/gcIpbUUzPNXpfKl7mQitw==";
    };
  };

  # System-wide SSH client config so BOTH the restic backup services and the
  # restic-exporter (which only sees RESTIC_REPOSITORY, with no per-repo
  # options) resolve the right port/key/known-hosts without depending on
  # $HOME (the exporter runs with ProtectHome=true). The user comes from the
  # sftp:user@host URL, so it is not hardcoded here.
  sshExtraConfig = config: sb: ''
    Host *.your-storagebox.de
      Port 23
      IdentityFile ${config.age.secrets."hetzner-storagebox".path}
      IdentitiesOnly yes
      StrictHostKeyChecking yes
      UserKnownHostsFile /etc/ssh/ssh_known_hosts

    Host storagebox
      HostName ${sb.host}
      User ${sb.user}
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
    let
      sb = config.constants.hosts.hyper.storageBox;
    in
    {
      # The secret itself is auto-discovered from secrets/hosts/hyper/*.age by
      # modules/features/security/secrets.nix (default owner root / mode 0400,
      # read by the root-run restic services) — no explicit declaration needed.
      programs.ssh.extraConfig = sshExtraConfig config sb;
      programs.ssh.knownHosts = mkKnownHosts sb.host;
    };

  flake.modules.darwin.hetznerStoragebox =
    { config, ... }:
    let
      sb = config.constants.hosts.hyper.storageBox;
    in
    {
      # On m4 the secret is auto-discovered from secrets/hosts/m4/*.age; override
      # the owner so the user can read the private key for interactive SSH.
      age.secrets."hetzner-storagebox".owner = "logikdev";
      programs.ssh.extraConfig = sshExtraConfig config sb;
      programs.ssh.knownHosts = mkKnownHosts sb.host;
    };
}
