{ ... }:
{
  flake.modules.nixos.gpu = {
    services.prometheus.exporters.nvidia-gpu = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9835;
    };

    notify.services = [ "prometheus-nvidia-gpu-exporter" ];
  };
}
