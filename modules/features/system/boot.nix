{
  flake.modules.nixos.common =
    { pkgs, ... }:
    {
      boot.loader.systemd-boot = {
        enable = true;

        configurationLimit = 5;
      };
      boot.loader.efi.canTouchEfiVariables = true;
      #boot.kernelPackages = pkgs.linuxPackages_6_17;
      hardware.enableRedistributableFirmware = true;
      #boot.kernelPackages = pkgs.linuxPackages_6_17; # ou linuxPackages_6_x selon ta version

      # Options de kernel pour Cilium / BPF
      boot.kernel.sysctl = {
        "net.core.bpf_jit_enable" = 1; # active le JIT BPF
        "net.core.bpf_jit_harden" = 0;
      };

      # Modules à charger automatiquement
      boot.kernelModules = [
        "cls_bpf" # nécessaire pour Cilium traffic control
        "act_bpf"
        "bpf_jit"
        "bpf_tc"
      ];

      # Si tu veux un kernel custom avec toutes les options
      # boot.kernelPatches = ''
      #   CONFIG_BPF=y
      #   CONFIG_BPF_SYSCALL=y
      #   CONFIG_NET_CLS_BPF=y
      #   CONFIG_NET_CLS_ACT=y
      #   CONFIG_NET_SCH_INGRESS=y
      #   CONFIG_BPF_JIT=y
      #   CONFIG_CGROUPS=y
      #   CONFIG_CGROUP_BPF=y
      #   CONFIG_CRYPTO_SHA1=y
      #   CONFIG_CRYPTO_USER_API_HASH=y
      #   CONFIG_PERF_EVENTS=y
      #   CONFIG_SCHEDSTATS=y
      # '';
    };
}
