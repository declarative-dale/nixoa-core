# vars.nix - TOML-based configuration
# ============================================================================
# Copy sample-nixoa.toml to nixoa.toml and customize your settings
# Uses builtins.fromTOML - simple and nix-native!
# ============================================================================

let
  # Check if nixoa.toml exists, otherwise use defaults
  configPath = ./nixoa.toml;
  configExists = builtins.pathExists configPath;

  # Load config if it exists
  userConfig = if configExists
    then builtins.fromTOML (builtins.readFile configPath)
    else {};

  # Helper to get value with fallback to default
  get = path: default:
    let
      getValue = config: pathList:
        if pathList == []
        then config
        else if builtins.isAttrs config && builtins.hasAttr (builtins.head pathList) config
        then getValue config.${builtins.head pathList} (builtins.tail pathList)
        else null;

      result = getValue userConfig path;
    in
      if result == null then default else result;

  # Filter out comments and examples from SSH keys list
  cleanSshKeys = keys:
    builtins.filter (key:
      !(builtins.isString key &&
        (builtins.substring 0 8 key == "_comment" ||
         builtins.substring 0 8 key == "_example"))
    ) keys;

in
{
  # ============================================================================
  # REQUIRED SETTINGS
  # ============================================================================

  system = get ["system"] "x86_64-linux";
  hostname = get ["hostname"] "xoa";
  username = get ["username"] "xoa";
  timezone = get ["timezone"] "UTC";

  # Filter out comment/example entries from SSH keys
  sshKeys = cleanSshKeys (get ["sshKeys"] []);

  # ============================================================================
  # XEN ORCHESTRA CONFIGURATION
  # ============================================================================

  xoHost = get ["xo" "host"] "0.0.0.0";
  xoPort = get ["xo" "port"] 80;
  xoHttpsPort = get ["xo" "httpsPort"] 443;
  enableV6Preview = get ["xo" "enableV6Preview"] false;

  tls = {
    enable = get ["tls" "enable"] true;
    redirectToHttps = get ["tls" "redirectToHttps"] true;
    dir = get ["tls" "dir"] "/etc/ssl/xo";
    cert = get ["tls" "cert"] "/etc/ssl/xo/certificate.pem";
    key = get ["tls" "key"] "/etc/ssl/xo/key.pem";
  };

  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================

  networking = {
    firewall = {
      allowedTCPPorts = get ["networking" "firewall" "allowedTCPPorts"] [80 443 3389 5900 8012];
    };
  };

  # ============================================================================
  # STORAGE & MOUNTING
  # ============================================================================

  storage = {
    nfs.enable = get ["storage" "nfs" "enable"] true;
    cifs.enable = get ["storage" "cifs" "enable"] true;
    mountsDir = get ["storage" "mountsDir"] "/var/lib/xo/mounts";
  };

  # ============================================================================
  # TERMINAL ENHANCEMENTS
  # ============================================================================

  extras = {
    enable = get ["extras" "enable"] false;
  };

  # ============================================================================
  # AUTOMATED UPDATES
  # ============================================================================

  updates = {
    repoDir = get ["updates" "repoDir"] "~/nixoa";
    protectPaths = get ["updates" "protectPaths"] ["hardware-configuration.nix"];

    monitoring = {
      notifyOnSuccess = get ["updates" "monitoring" "notifyOnSuccess"] false;

      email = {
        enable = get ["updates" "monitoring" "email" "enable"] false;
        to = get ["updates" "monitoring" "email" "to"] "admin@example.com";
      };

      ntfy = {
        enable = get ["updates" "monitoring" "ntfy" "enable"] false;
        server = get ["updates" "monitoring" "ntfy" "server"] "https://ntfy.sh";
        topic = get ["updates" "monitoring" "ntfy" "topic"] "xoa-updates";
      };

      webhook = {
        enable = get ["updates" "monitoring" "webhook" "enable"] false;
        url = get ["updates" "monitoring" "webhook" "url"] "";
      };
    };

    gc = {
      enable = get ["updates" "gc" "enable"] false;
      schedule = get ["updates" "gc" "schedule"] "Sun 04:00";
      keepGenerations = get ["updates" "gc" "keepGenerations"] 7;
    };

    flake = {
      enable = get ["updates" "flake" "enable"] false;
      schedule = get ["updates" "flake" "schedule"] "Sun 04:00";
      remoteUrl = get ["updates" "flake" "remoteUrl"] "https://codeberg.org/dalemorgan/declarative-xoa-ce.git";
      branch = get ["updates" "flake" "branch"] "main";
      autoRebuild = get ["updates" "flake" "autoRebuild"] false;
    };

    nixpkgs = {
      enable = get ["updates" "nixpkgs" "enable"] false;
      schedule = get ["updates" "nixpkgs" "schedule"] "Mon 04:00";
      keepGenerations = get ["updates" "nixpkgs" "keepGenerations"] 7;
    };

    xoa = {
      enable = get ["updates" "xoa" "enable"] false;
      schedule = get ["updates" "xoa" "schedule"] "Tue 04:00";
      keepGenerations = get ["updates" "xoa" "keepGenerations"] 7;
    };

    libvhdi = {
      enable = get ["updates" "libvhdi" "enable"] false;
      schedule = get ["updates" "libvhdi" "schedule"] "Wed 04:00";
      keepGenerations = get ["updates" "libvhdi" "keepGenerations"] 7;
    };
  };

  # ============================================================================
  # SERVICE ACCOUNT SETTINGS
  # ============================================================================

  xoUser = get ["service" "xoUser"] "xo";
  xoGroup = get ["service" "xoGroup"] "xo";

  # ============================================================================
  # CUSTOM PACKAGES
  # ============================================================================

  packages = {
    system.extra = get ["packages" "system" "extra"] [];
    user.extra = get ["packages" "user" "extra"] [];
  };

  # ============================================================================
  # CUSTOM SERVICES
  # ============================================================================

  # Read all service configurations from TOML
  # This includes both simple enables and detailed configurations
  customServices =
    let
      # Get the services section from config, excluding the 'enable' list
      servicesConfig = if builtins.hasAttr "services" userConfig
                       then builtins.removeAttrs userConfig.services ["enable"]
                       else {};

      # Get the simple enable list
      enableList = get ["services" "enable"] [];

      # Convert enable list to attribute set with enable = true
      enabledServices = builtins.listToAttrs (
        map (serviceName: {
          name = serviceName;
          value = { enable = true; };
        }) enableList
      );
    in
      # Merge enabled services with detailed configs (detailed configs take precedence)
      enabledServices // servicesConfig;

  # ============================================================================
  # NIXOS STATE VERSION
  # ============================================================================

  stateVersion = get ["stateVersion"] "25.05";
}
