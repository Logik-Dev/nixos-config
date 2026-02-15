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
  yazi.props.cwd = "/Users/logikdev";

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

in
{
  flake.modules.homeManager.desktop =
    { pkgs, isDarwin, ... }:
    {
      programs.zellij = {
        enable = false;
        enableFishIntegration = true;
        attachExistingSession = true;
        exitShellOnExit = true;
        settings.default_shell = "fish";
        settings.theme = "cyber-dark";
        # settings.default_layout = "nixos";
        # layouts = mapLayouts {
        #   nixos = {
        #     props.cwd = "/Users/logikdev/Homelab/Nixos";
        #     tabs = {
        #       inherit
        #         btop
        #         yazi
        #         vim
        #         hyper
        #         ;
        #     };
        #   };
        # };
      };
    };
}
