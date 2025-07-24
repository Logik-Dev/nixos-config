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
  
  wait_for {
    type = "agent"
  }

  profiles = [
    incus_profile.k3s_control_plane.name
  ]

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

# Output - Get IP from vlan11 interface specifically
output "k3s_control_plane_ip" {
  value = "10.11.0.100"
}
