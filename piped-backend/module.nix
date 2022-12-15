{ self }:
{ config
, pkgs
, lib
, options
, ...
}:

with lib;

let

  cfg = config.services.piped-backend;

  propsFormat = pkgs.formats.javaProperties {};

  autoProps = {
    PORT = builtins.toString cfg.listenPort;
    PROXY_PART = "http://${config.services.piped-proxy.listenAddress}";
    API_URL = "http://127.0.0.1:${builtins.toString cfg.listenPort}";
    FRONTEND_URL = "http://${config.services.piped-frontend.listenHost}:${toString config.services.piped-frontend.listenPort}";
    COMPROMISED_PASSWORD_CHECK = "false";
    MATRIX_SERVER = "";
    "hibernate.connection.url" = "jdbc:postgresql://${cfg.dbHost}:${builtins.toString cfg.dbPort}/${cfg.dbName}";
    "hibernate.connection.driver_class" = "org.postgresql.Driver";
    "hibernate.dialect" = "org.hibernate.dialect.PostgreSQLDialect";
    "hibernate.connection.username" = cfg.dbUser;
    "hibernate.connection.password" = cfg.dbPassword;
  };

  propsFile = propsFormat.generate "piped-backend-config.properties" (autoProps // cfg.properties);

in

{
  options.services.piped-backend = {

    enable = mkEnableOption "Whether to enable the piped-backend service";

    listenPort = mkOption {
      type = types.int;
      default = 14302;
    };

    dbName = mkOption {
      type = types.str;
      default = "piped";
    };

    dbUser = mkOption {
      type = types.str;
      default = "piped";
    };

    dbPassword = mkOption {
      type = types.str;
      default = "piped";
    };

    dbHost = mkOption {
      type = types.nullOr types.str;
      default = "127.0.0.1";
    };

    dbPort = mkOption {
      type = types.int;
      default = options.services.postgresql.port.default;
    };

    # https://github.com/TeamPiped/Piped-Backend/blob/master/src/main/java/me/kavin/piped/consts/Constants.java
    properties = mkOption {
      inherit (propsFormat) type;
      default = {};
    };

    package = mkOption {
      type = types.package;
      default = self.packages."${pkgs.stdenv.system}".piped-backend;
    };

  };

  config = mkIf cfg.enable {
    systemd.services.piped-backend = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStartPre = [
          #"psql
        ];
        ExecStart = "${cfg.package}/bin/piped-backend";
        RuntimeDirectory = [ "%N" ];
        BindReadOnlyPaths = [
          "${propsFile}:%t/%N/config.properties"
        ];
        WorkingDirectory = [ "%t/%N" ];
        DynamicUser = true;
        User = "piped-backend";
      };
    };

    services.postgresql = {
      enable = true;
      enableTCPIP = true;
      ensureDatabases = lib.singleton cfg.dbName;
      ensureUsers = lib.singleton {
        name = cfg.dbUser;
        ensurePermissions = {
          "DATABASE ${cfg.dbName}" = "ALL PRIVILEGES";
        };
      };
      # This is only needed because the unix user invidious isn't the same as
      # the database user. This tells postgres to map one to the other.
      identMap = ''
        piped-backend piped-backend ${cfg.dbUser}
      '';
      # And this specifically enables peer authentication for only this
      # database, which allows passwordless authentication over the postgres
      # unix socket for the user map given above.
      authentication = ''
        local ${cfg.dbName} ${cfg.dbUser} peer map=piped-backend
      '';
    };

    nixpkgs.config.piped = {
      backendUrl = cfg.properties.API_URL;
      frontendUrl = cfg.properties.FRONTEND_URL;
    };

  };
}