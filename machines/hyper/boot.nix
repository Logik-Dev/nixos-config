{
  # Boot loader configuration
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 5;
  };

  # GPU Passthrough kernel parameters and modules
  boot.kernelParams = [
    "intel_iommu=on"
    "iommu=pt"
  ];
  boot.kernelModules = [ "vfio" "vfio_pci" "vfio_iommu_type1" "vfio_virqfd" ];
  boot.extraModprobeConfig = ''
    options vfio-pci ids=10de:1bb1,10de:10f0 disable_vga=1
  '';
}
