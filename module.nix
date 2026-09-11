{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.pangolin;
  format = pkgs.formats.yaml { };

  baseConfig = {
    app.dashboard_url = "https://${cfg.dashboardDomain}";
    domains.domain1 = {
      base_domain = cfg.baseDomain;
      prefer_wildcard_cert = false;
    };
    server = {
      external_port = cfg.ports.external;
      internal_port = cfg.ports.internal;
      next_port = cfg.ports.next;
      integration_port = cfg.ports.integration;
      internal_hostname = cfg.internalHostname;
    };
    gerbil.base_endpoint = cfg.dashboardDomain;
    flags.enable_integration_api = false;
  };

  finalConfig = lib.recursiveUpdate baseConfig cfg.settings;
  configFile = format.generate "config.yml" finalConfig;

  adminSeeder = pkgs.writeShellScript "pangolin-seed-admin" ''
    set -e
    if [ -f "${cfg.initialAdmin.passwordFile}" ]; then
      PASSWORD=$(cat "${cfg.initialAdmin.passwordFile}")
      echo "Seeding Pangolin initial admin account (${cfg.initialAdmin.email})..."
      PANGOLIN_DATA_DIR="${cfg.dataDir}" ${cfg.package}/bin/pangctl set-admin-credentials \
        --email "${cfg.initialAdmin.email}" \
        --password "$PASSWORD" 2>/dev/null || true
    fi
  '';
in
{
  options.services.pangolin = {
    enable = mkEnableOption "Pangolin reverse proxy with identity and access control";

    package = mkOption {
      type = types.package;
      default = pkgs.pangolin or pkgs.fosrl-pangolin;
      description = "The Pangolin package to use.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/pangolin";
      description = "State and working directory for Pangolin.";
    };

    user = mkOption {
      type = types.str;
      default = "pangolin";
      description = "User to run Pangolin as.";
    };

    group = mkOption {
      type = types.str;
      default = "fossorial";
      description = "Group to run Pangolin as.";
    };

    baseDomain = mkOption {
      type = types.str;
      default = "example.com";
      description = "Base domain for Pangolin tunnel endpoints.";
    };

    dashboardDomain = mkOption {
      type = types.str;
      default = "pangolin.${cfg.baseDomain}";
      description = "FQDN for the Pangolin dashboard interface.";
    };

    internalHostname = mkOption {
      type = types.str;
      default = "localhost";
      description = "Internal hostname for service communication.";
    };

    ports = {
      external = mkOption {
        type = types.port;
        default = 3000;
        description = "Dashboard API & external listening port.";
      };
      internal = mkOption {
        type = types.port;
        default = 3005;
        description = "Internal communication port (defaults to 3005 to prevent conflict with Grafana 3001).";
      };
      next = mkOption {
        type = types.port;
        default = 3002;
        description = "Next.js Web UI internal listening port.";
      };
      integration = mkOption {
        type = types.port;
        default = 3003;
        description = "Integration API listening port.";
      };
    };

    serverSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing SERVER_SECRET. If null, one is automatically generated and persisted.";
    };

    setupToken = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Static 32-character setup token (PANGOLIN_SETUP_TOKEN).";
    };

    setupTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing PANGOLIN_SETUP_TOKEN.";
    };

    initialAdmin = {
      enable = mkEnableOption "declarative creation of initial server administrator";
      email = mkOption {
        type = types.str;
        default = "admin@${cfg.baseDomain}";
        description = "Email address for initial server admin account.";
      };
      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing password for initial admin.";
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open external API (3000) and WebUI (3002) ports in firewall.";
    };

    caddy = {
      enable = mkEnableOption "automatic Caddy reverse proxy integration for Pangolin WebUI";
      domain = mkOption {
        type = types.str;
        default = cfg.dashboardDomain;
        description = "Virtual host domain in Caddy.";
      };
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Extra configuration overrides for config.yml.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.${cfg.group} = { };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        cfg.ports.external
        cfg.ports.next
      ];
    };

    services.caddy.virtualHosts = mkIf cfg.caddy.enable {
      "${cfg.caddy.domain}".extraConfig = ''
        reverse_proxy 127.0.0.1:${toString cfg.ports.next}
      '';
    };

    systemd.services.pangolin = {
      description = "Pangolin reverse proxy tunneling service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = {
        PANGOLIN_DATA_DIR = cfg.dataDir;
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        Restart = "always";
        RestartSec = "5s";

        # Systemd hardening without the broken SocketBindDeny=ipv4:tcp
        ProtectSystem = "full";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        RestrictRealtime = true;
        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
          "AF_UNIX"
        ];
        SocketBindDeny = [
          "ipv4:udp"
          "ipv6:udp"
        ];
      };

      preStart = ''
        mkdir -p "${cfg.dataDir}/config"
        cp -f "${configFile}" "${cfg.dataDir}/config/config.yml"
        chmod 600 "${cfg.dataDir}/config/config.yml"

        ENV_FILE="${cfg.dataDir}/pangolin.env"
        touch "$ENV_FILE"
        chmod 600 "$ENV_FILE"

        ${if cfg.serverSecretFile != null then ''
          SERVER_SECRET=$(cat "${cfg.serverSecretFile}")
          grep -v '^SERVER_SECRET=' "$ENV_FILE" > "$ENV_FILE.tmp" || true
          echo "SERVER_SECRET=$SERVER_SECRET" >> "$ENV_FILE.tmp"
          mv "$ENV_FILE.tmp" "$ENV_FILE"
        '' else ''
          if ! grep -q '^SERVER_SECRET=' "$ENV_FILE" 2>/dev/null; then
            RAND_SECRET=$(${pkgs.openssl}/bin/openssl rand -hex 32)
            echo "SERVER_SECRET=$RAND_SECRET" >> "$ENV_FILE"
          fi
        ''}

        ${optionalString (cfg.setupToken != null) ''
          grep -v '^PANGOLIN_SETUP_TOKEN=' "$ENV_FILE" > "$ENV_FILE.tmp" || true
          echo "PANGOLIN_SETUP_TOKEN=${cfg.setupToken}" >> "$ENV_FILE.tmp"
          mv "$ENV_FILE.tmp" "$ENV_FILE"
        ''}

        ${optionalString (cfg.setupTokenFile != null) ''
          SETUP_TOKEN=$(cat "${cfg.setupTokenFile}")
          grep -v '^PANGOLIN_SETUP_TOKEN=' "$ENV_FILE" > "$ENV_FILE.tmp" || true
          echo "PANGOLIN_SETUP_TOKEN=$SETUP_TOKEN" >> "$ENV_FILE.tmp"
          mv "$ENV_FILE.tmp" "$ENV_FILE"
        ''}

        chown -R ${cfg.user}:${cfg.group} "${cfg.dataDir}"
      '';

      script = ''
        set -a
        if [ -f "${cfg.dataDir}/pangolin.env" ]; then
          . "${cfg.dataDir}/pangolin.env"
        fi
        set +a
        exec ${cfg.package}/bin/pangolin
      '';

      postStart = optionalString (cfg.initialAdmin.enable && cfg.initialAdmin.passwordFile != null) ''
        # Allow service 3 seconds to spin up database and migrations
        sleep 3
        ${adminSeeder}
      '';
    };
  };
}
