variable "storage_pools" {
  description = "Incus pools"
  type = object({
    btrfs_pool = string
    lvm_pool   = string
  })
}

variable "profiles" {
  description = "Profiles associated with the instance"
  type        = set(string)
}

variable "incus_profiles" {
  description = "Map of all incus profiles"
  type        = map(string)
}

variable "type" {
  description = "Type of the instance: container or virtual-machine"
  type        = string
}

variable "hostname" {
  description = "Hostname and name of the instance"
  type        = string
}

variable "username" {
  description = "Admin username"
  type        = string
}

variable "email" {
  description = "Admin email"
  type        = string
}

variable "domain" {
  description = "Main domain"
  type        = string
}

variable "images" {
  description = "Incus images"
  type = object({
    container       = string
    virtual-machine = string
  })
}

variable "vlan" {
  description = "VLAN for main NIC"
  type        = number
}

variable "hwaddr" {
  description = "MAC address for main NIC"
  type        = string
}

variable "size" {
  description = "Size of the root disk"
  type        = string
}

variable "cpus" {
  description = "CPU's assigned to the instance"
  type        = string
}

variable "memory" {
  description = "Memory assigned to the container"
  type        = string
}



