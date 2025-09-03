{
  # OpenSSH configuration
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.PasswordAuthentication = false;
  security.pam.sshAgentAuth.enable = true;
}
