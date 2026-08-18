{pkgs}:
pkgs.writeShellApplication {
  name = "nixoa-ci-installer-boot";
  runtimeInputs = with pkgs; [
    bash
    coreutils
    gnugrep
    qemu_kvm
  ];
  text = builtins.readFile ./installer-boot.sh;
  meta.description = "Boot-test the NiXOA installer with flake-provided QEMU";
}
