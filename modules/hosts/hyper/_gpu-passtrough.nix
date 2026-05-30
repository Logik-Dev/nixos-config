{
  flake.modules.nixos.hyper = {
    boot.kernelParams = [
      "intel_iommu=on"
      "iommu=pt"
    ];
    boot.kernelModules = [
      "vfio"
      "vfio_pci"
      "vfio_iommu_type1"
      "vfio_virqfd"
    ];
    boot.extraModprobeConfig = ''
      options vfio-pci ids=10de:1bb1,10de:10f0 disable_vga=1
    '';
  };

}
