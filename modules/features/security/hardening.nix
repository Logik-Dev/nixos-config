{
  flake.modules.nixos.hardening = {
    # Passwordless sudo for wheel: kept on purpose. Remote deploys run
    # `nh os switch` over a non-interactive SSH session, and requiring a
    # password would only protect against SSH-key compromise — which is moot
    # here since a NOPASSWD deploy path (or the key itself) is already
    # root-equivalent for a single-admin host.
    security.sudo.wheelNeedsPassword = false;
    users.users.root.hashedPassword = "!";

    # Compressed RAM swap as an OOM safety net, not a performance tweak: hyper
    # has 62 GB RAM and no disk swap, so a memory spike (Immich ML, a runaway
    # Postgres query, restic holding cache) would hit the OOM killer with no
    # overflow valve. A small zstd zram device gives the kernel somewhere to
    # push cold anon pages — fast, no SSD wear. Kept modest (25%): with this
    # much RAM a large device would only ever sit idle.
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 25;
    };
  };

  flake.modules.darwin.common = {
    security.pam.services.sudo_local.touchIdAuth = true;
  };
}
