{ lib ? (import <nixpkgs> {}).lib }:

let
  # Parse a .env file into an attribute set
  # Returns an empty set if file doesn't exist
  parseEnvFile = path:
    let
      # Check if file exists
      fileExists = builtins.pathExists path;

      # Read file content if it exists
      content = if fileExists then builtins.readFile path else "";

      # Split into lines
      lines = lib.splitString "\n" content;

      # Filter out comments and empty lines
      validLines = builtins.filter (line:
        line != "" &&
        !(lib.hasPrefix "#" (lib.trim line)) &&
        (lib.hasInfix "=" line)
      ) lines;

      # Parse each line into key-value pair
      parseLine = line:
        let
          parts = lib.splitString "=" line;
          key = lib.trim (builtins.head parts);
          # Join remaining parts in case value contains '='
          value = lib.trim (lib.concatStringsSep "=" (builtins.tail parts));
          # Remove quotes if present
          cleanValue =
            if (lib.hasPrefix "\"" value && lib.hasSuffix "\"" value) ||
               (lib.hasPrefix "'" value && lib.hasSuffix "'" value)
            then lib.substring 1 ((lib.stringLength value) - 2) value
            else value;
        in
          { name = key; value = cleanValue; };

      # Convert lines to attribute set
      pairs = map parseLine validLines;
    in
      if fileExists
      then builtins.listToAttrs pairs
      else {};

  # Get environment variable with default
  getEnv = name: default:
    let
      value = builtins.getEnv name;
    in
      if value != "" then value else default;

  # Get environment variable as boolean
  getEnvBool = name: default:
    let
      value = builtins.getEnv name;
      lower = lib.toLower value;
    in
      if value == "" then default
      else if lower == "true" || lower == "1" || lower == "yes" then true
      else if lower == "false" || lower == "0" || lower == "no" then false
      else default;

  # Get environment variable as integer
  getEnvInt = name: default:
    let
      value = builtins.getEnv name;
    in
      if value == "" then default
      else lib.toInt value;

  # Get environment variable as list (comma-separated)
  getEnvList = name: default:
    let
      value = builtins.getEnv name;
    in
      if value == "" then default
      else map lib.trim (lib.splitString "," value);

  # Get boolean from attribute set with fallback to environment variable
  getBool = env: name: default:
    let
      envValue = env.${name} or "";
      lower = lib.toLower envValue;
    in
      if envValue == "" then default
      else if lower == "true" || lower == "1" || lower == "yes" then true
      else if lower == "false" || lower == "0" || lower == "no" then false
      else default;

  # Get integer from attribute set with fallback
  getInt = env: name: default:
    let
      envValue = env.${name} or "";
    in
      if envValue == "" then default
      else lib.toInt envValue;

  # Get string from attribute set with fallback
  getString = env: name: default:
    env.${name} or default;

  # Get list from attribute set (comma-separated) with fallback
  getList = env: name: default:
    let
      envValue = env.${name} or "";
    in
      if envValue == "" then default
      else map lib.trim (lib.splitString "," envValue);

  # Collect all SSH keys from environment variables (SSH_KEY_1, SSH_KEY_2, etc.)
  collectSshKeys = env:
    let
      # Try to get SSH_KEY_1 through SSH_KEY_10
      possibleKeys = lib.genList (i: "SSH_KEY_${toString (i + 1)}") 10;
      # Filter out empty values
      keys = builtins.filter (key: key != "") (map (name: getString env name "") possibleKeys);
    in
      keys;

in
{
  inherit parseEnvFile;
  inherit getEnv getEnvBool getEnvInt getEnvList;
  inherit getBool getInt getString getList;
  inherit collectSshKeys;
}
