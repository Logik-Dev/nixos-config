variable "type" {
  description = "Type of the instance: container or virtual-machine"
  type        = string
  default     = "container"
}

variable "hostname" {
  description = "Hostname of the instance"
  type        = string
}

variable "image" {
  description = "Base image for the instance"
  type        = string
}

variable "vlan" {
  description = "VLAN for main NIC"
  type        = number
  default     = 11
}

variable "hwaddr" {
  description = "MAC address for main NIC"
  type        = string
}

variable "root_disk_pool" {
  description = "Storage pool for the root disk"
  type        = string
  default     = "btrfs_pool"
}

variable "size" {
  description = "Size of the root disk"
  type        = string
  default     = "20GiB"
}

variable "cpus" {
  description = "CPU's assigned to the instance"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory assigned to the container"
  type        = string
  default     = "4GiB"
}

