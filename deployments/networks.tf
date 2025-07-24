# VLAN 11 Kubernetes
resource "incus_network" "vlan11_k8s" {
  description = "Network on vlan11 for kubernetes nodes"
  name = "vlan11-k8s"
  type = "bridge"

  config = {
    "bridge.external_interfaces" = "enp4s0.11/enp4s0/11"
    "ipv4.address" = "none"
    "ipv6.address" = "none"
    "ipv4.dhcp.gateway" = "192.168.11.1"
    "ipv4.firewall" = "false"
  }
}

# VLAN 12 Ingress
resource "incus_network" "vlan12_ingress" {
  description = "Network on vlan12 for ingress"
  name = "vlan12-ingress"
  type = "bridge"

  config = {
    "bridge.external_interfaces" = "enp4s0.12/enp4s0/12"
    "ipv4.address" = "none"
    "ipv6.address" = "none"
    "ipv4.dhcp.gateway" = "192.168.12.1"
    "ipv4.firewall" = "false"

  }
}

# VLAN 21 IoT
resource "incus_network" "vlan21_iot" {
  description = "Network on vlan21 for IoT"
  name = "vlan21-iot"
  type = "bridge"

  config = {
    "bridge.external_interfaces" = "enp4s0.21/enp4s0/21"
    "ipv4.address" = "none"
    "ipv6.address" = "none"
    "ipv4.dhcp.gateway" = "192.168.21.1"
    "ipv4.firewall" = "false"


  }
}
