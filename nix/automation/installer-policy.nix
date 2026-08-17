{
  # Ordered shell patterns that never change the immutable installer output.
  ignoredChangePatterns = [
    "AGENTS.md"
    "LICENSE"
    "VERSION"
    "README*"
    "CHANGELOG*"
    "secretspec.toml"
    "docs/*"
    "packer/*"
    "tests/*"
    "modules/outputs/checks.nix"
    "modules/outputs/dev-shells.nix"
    "nix/checks/*"
    "nix/automation/github/*"
    ".github/*"
  ];

  # Git-index paths whose modes, blob IDs, and names define reusable installer
  # state. Keep exclusions explicit so test/check-only edits reuse artifacts.
  buildInputPaths = [
    ".github/workflows/ci.yml"
    "flake.lock"
    "flake.nix"
    "host"
    "installer"
    "modules"
    ":(exclude)modules/outputs/checks.nix"
    ":(exclude)modules/outputs/dev-shells.nix"
    "nix/automation"
    ":(exclude)nix/automation/github"
    "pkgs"
    "scripts"
  ];
}
