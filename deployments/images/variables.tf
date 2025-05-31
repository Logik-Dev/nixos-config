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

