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

resource "incus_profile" "vlan21_iot" {
  name = "vlan21-iot"
  description = "VLAN21 network profile for IoT"

  device {
    name = "eth2"
    type = "nic"

    properties = {
      network = incus_network.vlan21_iot.name
    }
  }
}


