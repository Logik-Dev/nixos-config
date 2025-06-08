module "sonicmaster" {
  source = "./nixos_rebuild"
  ipv4   = "127.0.0.1"
  special_args = {
    hostname     = "sonicmaster"
    username     = nonsensitive(local.username)
    email        = nonsensitive(local.email)
    domain       = nonsensitive(local.domain)
    hetzner_user = nonsensitive(local.hetzner_user)
  }
}
