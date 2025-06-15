
variable "encryption_key" {
  sensitive = true
}

terraform {
  encryption {
    method "unencrypted" "migrate" {}

    key_provider "pbkdf2" "key" {
      passphrase = var.encryption_key
    }

    method "aes_gcm" "new_method" {
      keys = key_provider.pbkdf2.key
    }

    state {
      method   = method.aes_gcm.new_method
      enforced = true
    }
  }
}
