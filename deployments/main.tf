locals {
  machines = jsondecode(file("./machines.json"))
}

# ssh private keys in machine secrets
data "sops_file" "ssh_keys" {
  for_each    = local.machines
  source_file = "../machines/${each.key}/secrets.yaml"
}


# instance
resource "incus_instance" "instance" {
  for_each = local.machines
  name     = each.key
  type     = each.value.platform
  image    = each.value.platform == "container" ? "nixos/custom/container" : "nixos/custom/vm"
  profiles = []

  # nic with vlan
  device {
    name = "eth0"
    type = "nic"
    properties = {
      nictype = "macvlan"
      parent  = "enp4s0"
      vlan    = each.value.vlan
      hwaddr  = each.value.hwaddr
    }
  }

  # root disk
  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = each.value.pool
      size = each.value.size
    }
  }

  # config
  config = {
    "boot.autostart"     = true
    "limits.cpu"         = each.value.cpu
    "limits.memory"      = each.value.memory
    "snapshots.schedule" = "@startup, @daily"
    "snapshots.expiry"   = "4w"
  }

  wait_for {
    type = each.value.platform == "container" ? "ipv4" : "agent"
    nic  = each.value.platform == "container" ? "eth0" : null
  }

  # copy ssh host ed25519 private key to decrypt secrets
  file {
    content     = data.sops_file.ssh_keys[each.key].data["ssh_host_ed25519_key"]
    target_path = "/etc/ssh/ssh_host_ed25519_key"
    mode        = "0600"
    uid         = 0
    gid         = 0
  }

  # copy ssh host ed25519 public key
  file {
    source_path = "../machines/${each.key}/keys/ssh_host_ed25519_key.pub"
    target_path = "/etc/ssh/ssh_host_ed25519_key.pub"
    mode        = "0660"
    uid         = 0
    gid         = 0
  }

  # copy ssh host rsa private key to decrypt secrets
  file {
    content     = data.sops_file.ssh_keys[each.key].data["ssh_host_rsa_key"]
    target_path = "/etc/ssh/ssh_host_rsa_key"
    mode        = "0600"
    uid         = 0
    gid         = 0
  }

  # copy ssh host rsa public key
  file {
    source_path = "../machines/${each.key}/keys/ssh_host_rsa_key.pub"
    target_path = "/etc/ssh/ssh_host_rsa_key.pub"
    mode        = "0660"
    uid         = 0
    gid         = 0
  }

}


