# K3s Worker Nodes

# Load SSH keys from sops for worker1
data "sops_file" "k3s_worker1_secrets" {
  source_file = "../secrets/k3s-worker1.yaml"
}

# Load SSH keys from sops for worker2
data "sops_file" "k3s_worker2_secrets" {
  source_file = "../secrets/k3s-worker2.yaml"
}

# Worker1 VM
resource "incus_instance" "k3s_worker1" {
  name  = "k3s-worker1"
  image = incus_image.nixos_vm.fingerprint
  type  = "virtual-machine"
  
  wait_for {
    type = "agent"
  }

  profiles = [
    incus_profile.vlan11_k8s.name
  ]

  device {
    name = "eth0"
    type = "nic"
    
    properties = {
      network = incus_network.vlan11_k8s.name
      "hwaddr" = "BC:24:11:45:11:30"
    }
  }

  config = {
    "limits.cpu"       = "4"
    "limits.memory"    = "16GB"
    "boot.autostart"   = "true"
    "security.secureboot"  =  "false"
  }

  # SSH host private keys from SOPS
  file {
    content     = data.sops_file.k3s_worker1_secrets.data["ssh_host_rsa_key"]
    target_path = "/etc/ssh/ssh_host_rsa_key"
    mode        = "0600"
    uid         = 0
    gid         = 0
  }

  file {
    content     = data.sops_file.k3s_worker1_secrets.data["ssh_host_ed25519_key"]
    target_path = "/etc/ssh/ssh_host_ed25519_key"
    mode        = "0600"
    uid         = 0
    gid         = 0
  }

  # SSH host public keys from files
  file {
    content     = file("../machines/k3s-worker1/keys/ssh_host_rsa_key.pub")
    target_path = "/etc/ssh/ssh_host_rsa_key.pub"
    mode        = "0644"
    uid         = 0
    gid         = 0
  }

  file {
    content     = file("../machines/k3s-worker1/keys/ssh_host_ed25519_key.pub")
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

# Worker2 VM
resource "incus_instance" "k3s_worker2" {
  name  = "k3s-worker2"
  image = incus_image.nixos_vm.fingerprint
  type  = "virtual-machine"
  
  wait_for {
    type = "agent"
  }

  profiles = [
    incus_profile.vlan11_k8s.name
  ]

  device {
    name = "eth0"
    type = "nic"
    
    properties = {
      network = incus_network.vlan11_k8s.name
      "hwaddr" = "BC:24:11:45:11:31"
    }
  }

  config = {
    "limits.cpu"       = "4"
    "limits.memory"    = "16GB"
    "boot.autostart"   = "true"
    "security.secureboot"  =  "false"
  }

  # SSH host private keys from SOPS
  file {
    content     = data.sops_file.k3s_worker2_secrets.data["ssh_host_rsa_key"]
    target_path = "/etc/ssh/ssh_host_rsa_key"
    mode        = "0600"
    uid         = 0
    gid         = 0
  }

  file {
    content     = data.sops_file.k3s_worker2_secrets.data["ssh_host_ed25519_key"]
    target_path = "/etc/ssh/ssh_host_ed25519_key"
    mode        = "0600"
    uid         = 0
    gid         = 0
  }

  # SSH host public keys from files
  file {
    content     = file("../machines/k3s-worker2/keys/ssh_host_rsa_key.pub")
    target_path = "/etc/ssh/ssh_host_rsa_key.pub"
    mode        = "0644"
    uid         = 0
    gid         = 0
  }

  file {
    content     = file("../machines/k3s-worker2/keys/ssh_host_ed25519_key.pub")
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

# Deploy NixOS configuration to workers after creation
resource "null_resource" "deploy_k3s_worker1_config" {
  depends_on = [incus_instance.k3s_worker1, null_resource.deploy_k3s_control_plane_config]

  provisioner "local-exec" {
    command     = "sudo nixos-rebuild switch --flake .#k3s-worker1 --option builders \"\" --target-host logikdev@k3s-worker1 --use-remote-sudo"
    working_dir = ".."
  }
}

resource "null_resource" "deploy_k3s_worker2_config" {
  depends_on = [incus_instance.k3s_worker2, null_resource.deploy_k3s_control_plane_config]

  provisioner "local-exec" {
    command     = "sudo nixos-rebuild switch --flake .#k3s-worker2 --option builders \"\" --target-host logikdev@k3s-worker2 --use-remote-sudo"
    working_dir = ".."
  }
}

