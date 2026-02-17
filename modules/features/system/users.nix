{
  inputs,
  ...
}:
{
  flake.modules = inputs.self.factory.user "logikdev" true;
}
