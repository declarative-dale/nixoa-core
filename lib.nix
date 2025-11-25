# Pure evaluation mode compatible library
# Only uses builtins, no nixpkgs dependency

let
  # String manipulation helpers using only builtins

  # Split string by delimiter
  splitString = sep: str:
    let
      len = builtins.stringLength str;
      sepLen = builtins.stringLength sep;

      # Find first occurrence of separator
      findSep = pos:
        if pos > len - sepLen then null
        else if builtins.substring pos sepLen str == sep then pos
        else findSep (pos + 1);

      # Recursively split
      split' = pos:
        if pos >= len then []
        else
          let
            sepPos = findSep pos;
          in
            if sepPos == null
            then [ (builtins.substring pos (len - pos) str) ]
            else
              [ (builtins.substring pos (sepPos - pos) str) ] ++
              split' (sepPos + sepLen);
    in
      if str == "" then []
      else if sep == "" then [ str ]
      else split' 0;

  # Trim whitespace from string
  trim = str:
    let
      len = builtins.stringLength str;

      # Check if character is whitespace
      isWhitespace = c: c == " " || c == "\t" || c == "\n" || c == "\r";

      # Find first non-whitespace
      findStart = pos:
        if pos >= len then len
        else if isWhitespace (builtins.substring pos 1 str) then findStart (pos + 1)
        else pos;

      # Find last non-whitespace
      findEnd = pos:
        if pos < 0 then 0
        else if isWhitespace (builtins.substring pos 1 str) then findEnd (pos - 1)
        else pos + 1;

      start = findStart 0;
      end = findEnd (len - 1);
    in
      if start >= end then ""
      else builtins.substring start (end - start) str;

  # Check if string starts with prefix
  hasPrefix = prefix: str:
    let
      prefixLen = builtins.stringLength prefix;
      strLen = builtins.stringLength str;
    in
      if prefixLen > strLen then false
      else builtins.substring 0 prefixLen str == prefix;

  # Check if string ends with suffix
  hasSuffix = suffix: str:
    let
      suffixLen = builtins.stringLength suffix;
      strLen = builtins.stringLength str;
    in
      if suffixLen > strLen then false
      else builtins.substring (strLen - suffixLen) suffixLen str == suffix;

  # Check if string contains substring
  hasInfix = infix: str:
    let
      infixLen = builtins.stringLength infix;
      strLen = builtins.stringLength str;

      search = pos:
        if pos > strLen - infixLen then false
        else if builtins.substring pos infixLen str == infix then true
        else search (pos + 1);
    in
      search 0;

  # Convert to lowercase (basic ASCII only)
  toLower = str:
    let
      len = builtins.stringLength str;
      lowerChar = c:
        let code = builtins.substring 0 1 c; in
        if code == "A" then "a" else if code == "B" then "b"
        else if code == "C" then "c" else if code == "D" then "d"
        else if code == "E" then "e" else if code == "F" then "f"
        else if code == "G" then "g" else if code == "H" then "h"
        else if code == "I" then "i" else if code == "J" then "j"
        else if code == "K" then "k" else if code == "L" then "l"
        else if code == "M" then "m" else if code == "N" then "n"
        else if code == "O" then "o" else if code == "P" then "p"
        else if code == "Q" then "q" else if code == "R" then "r"
        else if code == "S" then "s" else if code == "T" then "t"
        else if code == "U" then "u" else if code == "V" then "v"
        else if code == "W" then "w" else if code == "X" then "x"
        else if code == "Y" then "y" else if code == "Z" then "z"
        else code;

      lower' = pos:
        if pos >= len then ""
        else lowerChar (builtins.substring pos 1 str) + lower' (pos + 1);
    in
      lower' 0;

  # Parse a .env file into an attribute set
  parseEnvFile = path:
    let
      # Check if file exists
      fileExists = builtins.pathExists path;

      # Read file content if it exists
      content = if fileExists then builtins.readFile path else "";

      # Split into lines
      lines = splitString "\n" content;

      # Filter out comments and empty lines
      validLines = builtins.filter (line:
        line != "" &&
        !(hasPrefix "#" (trim line)) &&
        (hasInfix "=" line)
      ) lines;

      # Parse each line into key-value pair
      parseLine = line:
        let
          parts = splitString "=" line;
          key = trim (builtins.head parts);
          # Join remaining parts in case value contains '='
          value = trim (builtins.concatStringsSep "=" (builtins.tail parts));
          # Remove quotes if present
          cleanValue =
            if (hasPrefix "\"" value && hasSuffix "\"" value) ||
               (hasPrefix "'" value && hasSuffix "'" value)
            then builtins.substring 1 ((builtins.stringLength value) - 2) value
            else value;
        in
          { name = key; value = cleanValue; };

      # Convert lines to attribute set
      pairs = map parseLine validLines;
    in
      if fileExists
      then builtins.listToAttrs pairs
      else {};

  # Get boolean from attribute set with fallback
  getBool = env: name: default:
    let
      envValue = env.${name} or "";
      lower = toLower envValue;
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
      else builtins.fromJSON envValue;

  # Get string from attribute set with fallback
  getString = env: name: default:
    env.${name} or default;

  # Get list from attribute set (comma-separated) with fallback
  getList = env: name: default:
    let
      envValue = env.${name} or "";
    in
      if envValue == "" then default
      else map trim (splitString "," envValue);

  # Collect all SSH keys from environment variables (SSH_KEY_1, SSH_KEY_2, etc.)
  collectSshKeys = env:
    let
      # Try to get SSH_KEY_1 through SSH_KEY_10
      possibleKeys = builtins.genList (i: "SSH_KEY_${toString (i + 1)}") 10;
      # Filter out empty values
      keys = builtins.filter (key: key != "") (map (name: getString env name "") possibleKeys);
    in
      keys;

in
{
  inherit parseEnvFile;
  inherit getBool getInt getString getList;
  inherit collectSshKeys;

  # Export string helpers for potential reuse
  inherit splitString trim hasPrefix hasSuffix hasInfix toLower;
}
