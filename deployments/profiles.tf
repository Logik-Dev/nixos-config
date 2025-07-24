resource "incus_profile" "vlan11_k8s" {
  name = "vlan11-k8s"
  description = "VLAN11 network profile for k8s nodes"

  device {
    name = "eth0"
    type = "nic"

    properties = {
      network = incus_network.vlan11_k8s.name
    }
  }
}

resource "incus_profile" "vlan12_ingress" {
  name = "vlan12-ingress"
  description = "VLAN12 network profile for ingress"

  device {
    name = "eth1"
    type = "nic"

    properties = {
      network = incus_network.vlan12_ingress.name
    }
  }
}

resource "incus_profile" "k3s_control_plane" {
  name = "k3s-control-plane"
  description = "K3s control plane profile with fixed MAC"

  device {
    name = "eth0"
    type = "nic"

    properties = {
      network = incus_network.vlan11_k8s.name
      "hwaddr" = "BC:24:11:45:11:29"
    }
  }
}