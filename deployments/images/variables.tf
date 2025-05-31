variable "type" {
  description = "Type of image to build: virtual-machine or container"
  type        = string
  default     = "container"
}

variable "hostname" {
  type      = string
  default   = "nixos"
  sensitive = false
  nullable  = false
}

variable "username" {
  type      = string
  sensitive = false
  nullable  = false
}

