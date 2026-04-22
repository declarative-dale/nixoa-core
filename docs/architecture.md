# Core Architecture

NiXOA core is both a reusable Den namespace and the concrete host flake for
NiXOA machines. Reusable behavior stays under exported Den aspects, while
host-owned data lives under `hosts/<hostname>/`.

## Repository Shape

```text
hosts/
├── default/
│   ├── default.nix
│   ├── context.nix
│   ├── settings.nix
│   ├── menu.nix
│   ├── host.nix
│   ├── user.nix
│   ├── hardware-configuration.nix
│   └── profiles/vm.nix
├── nixo-ce-example/
│   └── ...
modules/
├── dendritic.nix
├── namespace.nix
├── aspects/
├── hosts/
├── outputs/
└── nixos/
```

## Exported Namespace

`modules/namespace.nix` exports the reusable `nixoa` namespace:

- `flake.denful.nixoa.platform`
- `flake.denful.nixoa.virtualization`
- `flake.denful.nixoa.xen-orchestra`
- `flake.denful.nixoa.appliance`

`modules/aspects/defaults.nix` also keeps the Den defaults Den-native:

- `den.default.includes = [ <den/hostname> <den/define-user> ]`
- `den.ctx.user.includes = [ <den/mutual-provider> ]`

## Host Assembly

Concrete hosts are discovered from `hosts/` by `modules/hosts/default.nix`.
Every directory under `hosts/` except `hosts/default/` is imported as a host
owner module.

Each host's `default.nix`:

- loads host-local context from `context.nix`
- declares `den.hosts.<system>.<hostname>`
- includes `nixoa.appliance`
- attaches host-owned behavior through `includes`
- provides user-scoped behavior through `provides.to-users`
- emits a companion `-vm` host when the base host is not already a VM profile

This keeps composition inside Den's `includes` and `provides` model instead of
recreating a separate manual host-composition framework.

## Supporting Outputs

The flake also publishes:

- `nixosConfigurations.<hostname>` for concrete hosts
- repository and host-scoped `apps`
- `devShells`
- supporting `packages`

These outputs are secondary to the Den model, but they make the unified repo
operable without an additional wrapper flake.
