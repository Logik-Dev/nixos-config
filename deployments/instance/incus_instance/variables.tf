variable "type" {
  description = "Type of the instance: container or virtual-machine"
  type        = string
}

variable "name" {
  description = "Name of the instance"
  type        = string
}


variable "image" {
  description = "Base image for the instance"
  type        = string
}

variable "vlan" {
  description = "VLAN for main NIC"
  type        = number
}

variable "hwaddr" {
  description = "MAC address for main NIC"
  type        = string
}

variable "root_disk_pool" {
  description = "Storage pool for the root disk"
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

variable "profiles" {
  description = "Profiles associated with the instance"
  type        = set(string)
  default     = []
}

