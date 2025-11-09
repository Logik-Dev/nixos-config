{ lib, ... }:
let

  pane =
    args@{ ... }:
    {
      pane = args;
    };

  tab =
    name:
    {
      panes,
      props ? { },
      ...
    }:
    {
      tab = {
        _children = lib.mapAttrsToList (_: p: pane p) panes;
        _props = props // {
          inherit name;
        };
      };
    };

  layout =
    {
      tabs,
      props ? { },
      ...
    }:
    {
      layout = {
        _children = lib.mapAttrsToList mapTabs tabs;
        _props = props;
      };
    };

  mapTabs = name: args: tab name args;

  mapLayouts = attrs: lib.mapAttrs (_: value: layout value) attrs;

  yazi.panes.default.command = "yazi";

  btop = {
    panes.default.command = "btop";
  };

  vim = {
    props.focus = true;
    props.split_direction = "vertical";
    panes.right.size = "40%";
    panes.vim.command = "vi";
  };

  hyper = {
    panes.default.command = "ssh";
    panes.default.args = "192.168.10.100";
  };

  nixrepl = {
    panes.default.command = "nix";
    panes.default.args = "repl";
  };

  k8s =
    let
      cwd = "/home/logikdev/Homelab/k8s";
    in
    {
      props.split_direction = "vertical";

      panes.k9s = {
        inherit cwd;
        command = "k9s";
      };

      panes.k8s = {
        inherit cwd;
        size = "50%";
      };
    };

in
{
  flake.modules.homeManager.desktop = {
    programs.zellij = {
      enable = true;
      enableFishIntegration = true;
      attachExistingSession = true;
      exitShellOnExit = true;
      settings.theme = "cyber-dark";
      settings.default_layout = "k8s";
      layouts = mapLayouts {
        nixos = {
          props.cwd = "/home/logikdev/Homelab/Nixos";
          tabs = {
            inherit
              yazi
              vim
              nixrepl
              btop
              hyper
              ;
          };
        };
        k8s = {
          props.cwd = "/home/logikdev/Homelab/Nixos";
          tabs = {
            inherit
              vim
              k8s
              hyper
              ;
          };
        };
      };
    };
  };
}
