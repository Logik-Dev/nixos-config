{
  flake.modules.nixos.loki = {
    services.loki = {
      enable = true;
      dataDir = "/var/lib/loki";
      configuration = {
        auth_enabled = false;
        server = {
          http_listen_address = "127.0.0.1";
          http_listen_port = 3100;
        };

        common = {
          path_prefix = "/var/lib/loki";
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
          storage.filesystem = {
            chunks_directory = "/var/lib/loki/chunks";
            rules_directory = "/var/lib/loki/rules";
          };
        };

        schema_config.configs = [
          {
            from = "2020-10-24";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];

        limits_config = {
          retention_period = "720h";
          reject_old_samples = false;
          max_query_series = 5000;
          max_query_parallelism = 1;
        };

        compactor = {
          working_directory = "/var/lib/loki/compactor";
          delete_request_store = "filesystem";
        };
      };
    };

    notify.services = [ "loki" ];
  };
}
