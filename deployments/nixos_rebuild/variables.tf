variable "special_args" {
  description = "Nixos configuration's specials args"
  type = object({
    hostname     = string
    username     = string
    email        = string
    domain       = string
    hetzner_user = string
  })
}

variable "ipv4" {
  description = "IPv4 address of the host"
  type        = string
}
