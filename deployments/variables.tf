variable "github_owner" {
  description = "GitHub username/organization"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name for GitOps"
  type        = string
  default     = "k8s-homelab-gitops"
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}