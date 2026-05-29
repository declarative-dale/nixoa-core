{lib}: let
  boolFields = [
    "efiCanTouchVariables"
    "enableAutoCert"
    "enableCIFS"
    "enableExtras"
    "enableNFS"
    "enableTLS"
    "enableVHD"
    "enableXO"
    "enableXenGuest"
    "enableXenHardware"
    "nixoaMenuAutoStart"
    "sudoNoPassword"
  ];

  hostNameRe = "[A-Za-z0-9][A-Za-z0-9._-]*";
  userNameRe = "[a-z_][a-z0-9_-]*[$]?";
  packagePathRe = "[A-Za-z0-9_+.-]+(\\.[A-Za-z0-9_+.-]+)*";
  servicePathRe = "[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)*";
  sshPublicKeyRe = "[A-Za-z0-9._@+-]+ .+";

  matches = regex: value:
    builtins.isString value && builtins.match regex value != null;

  assertMsg = condition: message:
    assert lib.assertMsg condition message; true;

  validateEnum = name: allowed: value:
    assertMsg (builtins.elem value allowed)
    "NiXOA host context '${name}' must be one of ${lib.concatStringsSep ", " allowed}, got '${toString value}'";

  validateBool = context: name:
    assertMsg (builtins.isBool context.${name})
    "NiXOA host context '${name}' must be a boolean";

  validatePort = name: port:
    assertMsg (builtins.isInt port && port > 0 && port < 65536)
    "NiXOA host context '${name}' contains invalid TCP/UDP port '${toString port}'";

  validatePackage = name: item:
    assertMsg (
      ! builtins.isString item || matches packagePathRe item
    )
    "NiXOA host context '${name}' package '${toString item}' must be a non-empty pkgs attr path";

  validateService = name:
    assertMsg (matches servicePathRe name)
    "NiXOA host context enabled service '${toString name}' must be a non-empty services attr path";

  validateContext = context:
    assert validateEnum "hostSystem" ["x86_64-linux" "aarch64-linux"] context.hostSystem;
    assert validateEnum "deploymentProfile" ["physical" "vm"] context.deploymentProfile;
    assert validateEnum "bootLoader" ["systemd-boot" "grub" "none"] context.bootLoader;
    assert assertMsg (matches hostNameRe context.hostname) "NiXOA host context 'hostname' is not a valid host name";
    assert assertMsg (matches userNameRe context.username) "NiXOA host context 'username' is not a valid user name";
    assert assertMsg (builtins.isString context.repoDir && context.repoDir != "") "NiXOA host context 'repoDir' must be a non-empty path string";
    assert assertMsg (builtins.isString context.stateVersion && context.stateVersion != "") "NiXOA host context 'stateVersion' must be a non-empty string";
    assert assertMsg (builtins.isList context.sshKeys) "NiXOA host context 'sshKeys' must be a list";
    assert assertMsg (lib.all (matches sshPublicKeyRe) context.sshKeys) "NiXOA host context 'sshKeys' contains an invalid SSH public key";
    assert assertMsg (builtins.isList context.allowedTCPPorts) "NiXOA host context 'allowedTCPPorts' must be a list";
    assert assertMsg (builtins.isList context.allowedUDPPorts) "NiXOA host context 'allowedUDPPorts' must be a list";
    assert assertMsg (builtins.isList context.systemPackages) "NiXOA host context 'systemPackages' must be a list";
    assert assertMsg (builtins.isList context.extraSystemPackages) "NiXOA host context 'extraSystemPackages' must be a list";
    assert assertMsg (builtins.isList context.userPackages) "NiXOA host context 'userPackages' must be a list";
    assert assertMsg (builtins.isList context.extraUserPackages) "NiXOA host context 'extraUserPackages' must be a list";
    assert assertMsg (builtins.isList context.enabledServices) "NiXOA host context 'enabledServices' must be a list";
    assert lib.all (validateBool context) boolFields;
    assert lib.all (validatePort "allowedTCPPorts") context.allowedTCPPorts;
    assert lib.all (validatePort "allowedUDPPorts") context.allowedUDPPorts;
    assert lib.all (validatePackage "systemPackages") context.systemPackages;
    assert lib.all (validatePackage "extraSystemPackages") context.extraSystemPackages;
    assert lib.all (validatePackage "userPackages") context.userPackages;
    assert lib.all (validatePackage "extraUserPackages") context.extraUserPackages;
    assert lib.all validateService context.enabledServices; context;
in {
  normalize = context:
    validateContext (context
      // {
        allowedTCPPorts = lib.unique (context.allowedTCPPorts or []);
        allowedUDPPorts = lib.unique (context.allowedUDPPorts or []);
        enabledServices = lib.unique (context.enabledServices or []);
        extraSystemPackages = context.extraSystemPackages or [];
        extraUserPackages = context.extraUserPackages or [];
        flatpakRemotes = context.flatpakRemotes or [];
        flatpaks = context.flatpaks or [];
        systemPackages = context.systemPackages or [];
        userPackages = context.userPackages or [];
      });
}
