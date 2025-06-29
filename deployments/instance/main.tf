terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "0.3.1"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.2.0"
    }
  }
}


# ssh private keys
data "sops_file" "ssh_keys" {
  source_file = "../secrets/${var.hostname}.yaml"
}

# Instance
resource "incus_instance" "instance" {
  name     = var.hostname
  type     = var.type
  image    = var.images[var.type]
  profiles = var.profiles

  # nic with vlan
  device {
    name = "eth0"
    type = "nic"
    properties = {
      nictype = "macvlan"
      parent  = "enp4s0"
      vlan    = var.vlan
      hwaddr  = var.hwaddr
    }
  }

  # root disk
  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = var.storage_pools[var.type == "container" ? "btrfs_pool" : "lvm_pool"]
      size = var.size
    }
  }

  # config
  config = {
    "boot.autostart"      = true
    "security.secureboot" = var.type == "container" ? null : false
    "limits.cpu"          = var.cpus
    "limits.memory"       = var.memory
    "snapshots.schedule"  = "@weekly"
    "snapshots.expiry"    = "3w"
  }

  wait_for {
    type = var.type == "container" ? "ipv4" : "agent"
    nic  = var.type == "container" ? "eth0" : null
  }

  # copy ssh host ed25519 private key to decrypt secrets
  file {
    content     = data.sops_file.ssh_keys.data["ssh_host_ed25519_key"]
    target_path = "/etc/ssh/ssh_host_ed25519_key"
    mode        = "0600"
    uid         = 0
    gid         = 0
  }

  # copy ssh host ed25519 public key
  file {
    source_path = "../machines/${var.hostname}/keys/ssh_host_ed25519_key.pub"
    target_path = "/etc/ssh/ssh_host_ed25519_key.pub"
    mode        = "0660"
    uid         = 0
    gid         = 0
  }

  # copy ssh host rsa private key to decrypt secrets
  file {
    content     = data.sops_file.ssh_keys.data["ssh_host_rsa_key"]
    target_path = "/etc/ssh/ssh_host_rsa_key"
    mode        = "0600"
    uid         = 0
    gid         = 0
  }

  # copy ssh host rsa public key
  file {
    source_path = "../machines/${var.hostname}/keys/ssh_host_rsa_key.pub"
    target_path = "/etc/ssh/ssh_host_rsa_key.pub"
    mode        = "0660"
    uid         = 0
    gid         = 0
  }

  lifecycle {
    prevent_destroy = true
  }
}

output "ipv4" {
  value = incus_instance.instance.ipv4_address
}
