# vars.nix - User Configuration for XOA Deployment
# ============================================================================
# This file now reads configuration from .env file
# Copy sample.env to .env and configure your settings there
# ============================================================================

let
  # Import our helper library
  envLib = import ./lib.nix {};

  # Parse .env file from the same directory as this file
  # Returns empty set if .env doesn't exist
  env = envLib.parseEnvFile ./.env;

  # Helper functions for cleaner code
  getString = envLib.getString env;
  getBool = envLib.getBool env;
  getInt = envLib.getInt env;
  getList = envLib.getList env;

in
{
  # ============================================================================
  # REQUIRED SETTINGS - Configured via .env file
  # ============================================================================

  # System architecture
  system = getString "SYSTEM" "x86_64-linux";

  # Hostname for this NixOS system
  hostname = getString "HOSTNAME" "xoa";

  # Time zone (read from .env, default: UTC)
  timezone = getString "TIMEZONE" "UTC";

  # Admin username for SSH access (will have full sudo rights)
  username = getString "USERNAME" "xoa";

  # SSH public keys for admin user
  # Reads SSH_KEY_1, SSH_KEY_2, etc. from .env file
  sshKeys = envLib.collectSshKeys env;

  # ============================================================================
  # XEN ORCHESTRA CONFIGURATION
  # ============================================================================

  # Network binding (0.0.0.0 = all interfaces, 127.0.0.1 = localhost only)
  xoHost = getString "XO_HOST" "0.0.0.0";

  # Web interface ports
  xoPort = getInt "XO_PORT" 80;
  xoHttpsPort = getInt "XO_HTTPS_PORT" 443;

  # TLS/SSL configuration
  tls = {
    enable = getBool "TLS_ENABLE" true;
    redirectToHttps = getBool "TLS_REDIRECT_TO_HTTPS" true;
    dir = getString "TLS_DIR" "/etc/ssl/xo";
    cert = getString "TLS_CERT" "/etc/ssl/xo/certificate.pem";
    key = getString "TLS_KEY" "/etc/ssl/xo/key.pem";
  };

  # Enable Xen Orchestra v6 preview (accessible at /v6)
  enableV6Preview = getBool "ENABLE_V6_PREVIEW" false;

  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================

  networking = {
    firewall = {
      # Open ports for XO and console access
      # Reads comma-separated list from FIREWALL_TCP_PORTS in .env
      allowedTCPPorts = map (s:
        let n = builtins.fromJSON s;
        in if builtins.isInt n then n else builtins.throw "Invalid port: ${s}"
      ) (getList "FIREWALL_TCP_PORTS" [ "80" "443" "3389" "5900" "8012" ]);
    };
  };

  # ============================================================================
  # STORAGE & MOUNTING
  # ============================================================================

  storage = {
    nfs.enable = getBool "STORAGE_NFS_ENABLE" true;
    cifs.enable = getBool "STORAGE_CIFS_ENABLE" true;
    mountsDir = getString "STORAGE_MOUNTS_DIR" "/var/lib/xo/mounts";
  };

  # ============================================================================
  # TERMINAL ENHANCEMENTS
  # ============================================================================

  extras = {
    enable = getBool "EXTRAS_ENABLE" false;
  };

  # ============================================================================
  # AUTOMATED UPDATES
  # ============================================================================

  updates = {
    # Location of this flake repository
    repoDir = getString "UPDATES_REPO_DIR" "~/nixoa";

    # Files to protect from git operations
    # NOTE: vars.nix is no longer protected since personal info is in .env
    protectPaths = [ "hardware-configuration.nix" ];

    # Monitoring & Notifications
    monitoring = {
      notifyOnSuccess = getBool "UPDATES_NOTIFY_ON_SUCCESS" false;

      # Email notifications
      email = {
        enable = getBool "UPDATES_EMAIL_ENABLE" false;
        to = getString "UPDATES_EMAIL_TO" "admin@example.com";
      };

      # ntfy.sh push notifications
      ntfy = {
        enable = getBool "UPDATES_NTFY_ENABLE" false;
        server = getString "UPDATES_NTFY_SERVER" "https://ntfy.sh";
        topic = getString "UPDATES_NTFY_TOPIC" "xoa-updates";
      };

      # Webhook notifications
      webhook = {
        enable = getBool "UPDATES_WEBHOOK_ENABLE" false;
        url = getString "UPDATES_WEBHOOK_URL" "";
      };
    };

    # Garbage Collection
    gc = {
      enable = getBool "UPDATES_GC_ENABLE" false;
      schedule = getString "UPDATES_GC_SCHEDULE" "Sun 04:00";
      keepGenerations = getInt "UPDATES_GC_KEEP_GENERATIONS" 7;
    };

    # Flake Self-Update (pull from git)
    flake = {
      enable = getBool "UPDATES_FLAKE_ENABLE" false;
      schedule = getString "UPDATES_FLAKE_SCHEDULE" "Sun 04:00";
      remoteUrl = getString "UPDATES_FLAKE_REMOTE_URL" "https://codeberg.org/dalemorgan/declarative-xoa-ce.git";
      branch = getString "UPDATES_FLAKE_BRANCH" "main";
      autoRebuild = getBool "UPDATES_FLAKE_AUTO_REBUILD" false;
    };

    # NixOS Updates
    nixpkgs = {
      enable = getBool "UPDATES_NIXPKGS_ENABLE" false;
      schedule = getString "UPDATES_NIXPKGS_SCHEDULE" "Mon 04:00";
      keepGenerations = getInt "UPDATES_NIXPKGS_KEEP_GENERATIONS" 7;
    };

    # Xen Orchestra Updates
    xoa = {
      enable = getBool "UPDATES_XOA_ENABLE" false;
      schedule = getString "UPDATES_XOA_SCHEDULE" "Tue 04:00";
      keepGenerations = getInt "UPDATES_XOA_KEEP_GENERATIONS" 7;
    };

    # libvhdi Updates
    libvhdi = {
      enable = getBool "UPDATES_LIBVHDI_ENABLE" false;
      schedule = getString "UPDATES_LIBVHDI_SCHEDULE" "Wed 04:00";
      keepGenerations = getInt "UPDATES_LIBVHDI_KEEP_GENERATIONS" 7;
    };
  };

  # ============================================================================
  # SERVICE ACCOUNT SETTINGS
  # ============================================================================

  # XO service account (non-root, system user)
  xoUser = getString "XO_USER" "xo";
  xoGroup = getString "XO_GROUP" "xo";

  # ============================================================================
  # NIXOS STATE VERSION - DO NOT CHANGE
  # ============================================================================
  # This should match the NixOS version you initially installed with.
  stateVersion = getString "STATE_VERSION" "25.05";
}
