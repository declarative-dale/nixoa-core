{lib}: {
  selectedVmOutput = repoRoot: let
    automation = import (repoRoot + "/host/_automation/default.nix") {};
    selectedVmHost = automation.vmHost or null;
  in
    if selectedVmHost == null
    then null
    else "${selectedVmHost}-vm";

  vmAlias = attrs: selectedVmOutput:
    if selectedVmOutput != null && builtins.hasAttr selectedVmOutput attrs
    then {vm = attrs.${selectedVmOutput};}
    else {};
}
