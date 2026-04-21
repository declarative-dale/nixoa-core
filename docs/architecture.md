# Core Architecture

NiXOA core is a reusable Den namespace. It keeps plain NixOS implementation
modules under `modules/nixos/features/`, then exports those capabilities as a
NiXOA aspect tree under `flake.denful.nixoa`.

## Repository Shape

```text
modules/
├── dendritic.nix
├── namespace.nix
├── aspects/
│   ├── platform.nix
│   ├── virtualization.nix
│   ├── xen-orchestra.nix
│   └── appliance.nix
├── outputs/
│   └── packages.nix
└── nixos/features/
    ├── shared/
    ├── platform/
    ├── virtualization/
    └── xen-orchestra/
```

## Exported Namespace

`modules/namespace.nix` creates and exports the `nixoa` namespace:

- `flake.denful.nixoa.platform`
- `flake.denful.nixoa.virtualization`
- `flake.denful.nixoa.xen-orchestra`
- `flake.denful.nixoa.appliance`

Each aspect owns its NixOS-facing behavior directly:

- `platform`: base OS policy and shared packages
- `virtualization`: Xen guest and hardware integration
- `xen-orchestra`: XO modules plus the internal `pkgs.nixoa.*` overlay wiring
- `appliance`: includes the three reusable aspects above

## Relationship To System

`system/` imports core as a flake input, merges `flake.denful.nixoa` into its
local namespace, and includes the exported aspects from its host aspect:

- `imports = [ (inputs.den.namespace "nixoa" [ inputs.nixoaCore ]) ];`
- `den.aspects.${context.hostname}.includes = [ <nixoa/appliance> ];`

Host policy stays in `system/config/*`, which composes into `context` and is
passed to core's plain implementation modules through downstream NixOS
evaluation.

## Supporting Outputs

Core still publishes supporting packages from `modules/outputs/packages.nix`
for consumers that need build artifacts outside the aspect tree, but those are
secondary to the exported `nixoa` namespace.
