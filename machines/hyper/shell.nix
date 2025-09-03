{
  environment.shellAliases = {
    cat = "bat";
    l = "eza";
    ll = "eza -l";
    ls = "eza -l";
    lsh = "eza -la";
    llt = "eza -lT";
    tf = "noglob tofu";
    tfp = "noglob tofu plan";
    tfa = "noglob tofu apply";
    tfaa = "noglob tofu apply -auto-approve";
    tfat = "noglob tofu apply --target=";
    g = "git";
    ga = "git add";
    gl = "git log";
    gs = "git status";
    gcm = "git commit -m";
    gcam = "git commit --amend --no-edit";
    gcb = "git checkout -b";
    nos = "nh os switch -- --impure";
    not = "nh os test -- --impure";
    nrt = "nix run .#rebuild-target";
  };
}