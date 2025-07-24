terraform {
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.2.0"
    }
    incus = {
      source  = "lxc/incus"
      version = "0.3.1"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "~> 1.4.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "sops" {}


# FluxCD provider will be configured later with k3s kubeconfig

provider "github" {
  owner = var.github_owner
  token = var.github_token
}
