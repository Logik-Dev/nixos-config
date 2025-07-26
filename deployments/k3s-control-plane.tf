# K3s Control Plane VM

# Load SSH keys from sops
data "sops_file" "k3s_control_plane_secrets" {
  source_file = "../secrets/k3s-control-plane.yaml"
}

# Control Plane VM
resource "incus_instance" "k3s_control_plane" {
  name  = "k3s-control-plane"
  image = incus_image.nixos_vm.fingerprint
  type  = "virtual-machine"
 
  profiles = [
    incus_profile.vlan12_ingress.name,
    incus_profile.vlan21_iot.name
  ]

 
  wait_for {
    type = "agent"
  }

  device {
    name = "eth0"
    type = "nic"
    
    properties = {
      network = incus_network.vlan11_k8s.name
      "hwaddr" = "BC:24:11:45:11:29"
    }
  }

  config = {
    "limits.cpu"       = "4"
    "limits.memory"    = "8GB"
    "boot.autostart"   = "true"
    "security.secureboot"  =  "false"
  }

  # SSH host private keys from SOPS
  file {
    content     = data.sops_file.k3s_control_plane_secrets.data["ssh_host_rsa_key"]
    target_path = "/etc/ssh/ssh_host_rsa_key"
    mode        = "0600"
    uid         = 0
    gid         = 0
  }

  file {
    content     = data.sops_file.k3s_control_plane_secrets.data["ssh_host_ed25519_key"]
    target_path = "/etc/ssh/ssh_host_ed25519_key"
    mode        = "0600"
    uid         = 0
    gid         = 0
  }

  # SSH host public keys from files
  file {
    content     = file("../machines/k3s-control-plane/keys/ssh_host_rsa_key.pub")
    target_path = "/etc/ssh/ssh_host_rsa_key.pub"
    mode        = "0644"
    uid         = 0
    gid         = 0
  }

  file {
    content     = file("../machines/k3s-control-plane/keys/ssh_host_ed25519_key.pub")
    target_path = "/etc/ssh/ssh_host_ed25519_key.pub"
    mode        = "0644"
    uid         = 0
    gid         = 0
  }

  device {
    name = "root"
    type = "disk"
    
    properties = {
      path = "/"
      pool = incus_storage_pool.ultra.name
      size = "150GB"
    }
  }
}

# Deploy NixOS configuration after VM creation
resource "null_resource" "deploy_k3s_control_plane_config" {
  depends_on = [incus_instance.k3s_control_plane]

  provisioner "local-exec" {
    command     = "sudo nixos-rebuild switch --flake .#k3s-control-plane --option builders \"\" --target-host logikdev@k3s-control-plane --use-remote-sudo"
    working_dir = ".."
  }
}

# Copy kubeconfig to local machine after deployment
resource "null_resource" "sync_kubeconfig" {
  depends_on = [null_resource.deploy_k3s_control_plane_config]

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ~/.kube
      ssh logikdev@k3s-control-plane "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config.tmp
      sed 's/127.0.0.1/k3s-control-plane/g' ~/.kube/config.tmp > ~/.kube/config
      chmod 600 ~/.kube/config
      rm ~/.kube/config.tmp
    EOT
  }
}

# Install Cilium CNI via CLI after kubeconfig sync
resource "null_resource" "install_cilium" {
  depends_on = [null_resource.sync_kubeconfig]

  provisioner "local-exec" {
    command = "/home/logikdev/Nixos/scripts/install-cilium.sh"
  }

  # Trigger reinstall if configuration changes
  triggers = {
    cilium_config = md5(jsonencode({
        k8s_service_host = "192.168.11.100"
      l2_announcements = true
    }))
  }
}

