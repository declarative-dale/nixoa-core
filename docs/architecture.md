# Core Architecture

NiXOA core is both a reusable Den namespace and the concrete host flake for
NiXOA machines. Reusable behavior stays under exported Den aspects, while
host-owned data lives under `host/<hostname>/`.

## Repository Shape

```text
host/
├── _automation/
├── _template/
│   ├── default.nix
│   ├── _ctx/
│   ├── _homeManager/
│   └── _nixos/
├── nixo-ce-example/
│   └── ...
modules/
├── dendritic.nix
├── den-defaults.nix
├── host.nix
├── namespace.nix
├── nixoaCore/
├── schema.nix
├── outputs/
├── _homeManager/
└── _nixos/
```

## Exported Namespace

`modules/namespace.nix` exports the reusable `nixoaCore` namespace:

- `flake.denful.nixoaCore.platform`
- `flake.denful.nixoaCore.virtualization`
- `flake.denful.nixoaCore."xen-orchestra"`
- `flake.denful.nixoaCore.appliance`

The preferred consumption paths are:

- `<nixoaCore/platform>`
- `<nixoaCore/virtualization>`
- `<nixoaCore/xen-orchestra>`
- `<nixoaCore/appliance>`

`modules/den-defaults.nix` also keeps the Den defaults Den-native:

- `den.default.includes = [ <den/hostname> <den/define-user> ]`
- `den.ctx.user.includes = [ <den/mutual-provider> ]`

## Host Assembly

Concrete hosts are discovered from `host/` by `modules/host.nix`
through `inputs.import-tree`. Only non-underscored host owner modules are
loaded, so `host/_template/`, `host/_automation/`, and host-local `_ctx`,
`_nixos`, and `_homeManager` trees stay hidden until Den resolves them for a
class.

Each host's `default.nix`:

- merges host-local context from `_ctx/settings.nix` and `_ctx/menu.nix`
- declares `den.hosts.<system>.<hostname>`
- includes `<nixoaCore/appliance>`
- includes `(den._.import-tree ./.)` so host-owned `_nixos` and `_homeManager` trees project by class
- attaches host-owned behavior through `includes`
- provides user-scoped behavior through `provides.to-users`, keeping the host-owned Home Manager projection explicit for compatibility with the GitHub-released Den API
- emits both the concrete host and a companion `-vm` host

`host/_automation/default.nix` selects which concrete `-vm` output is re-exported
as the stable `nixosConfigurations.vm` automation target.

This keeps composition inside Den's `includes` and `provides` model instead of
recreating a separate manual host-composition framework.

## Supporting Outputs

The flake also publishes:

- `nixosConfigurations.<hostname>` for concrete hosts
- `nixosConfigurations.<hostname>-vm` for per-host VM variants
- `nixosConfigurations.vm` for automation that should not depend on a concrete host name
- repository and host-scoped `apps`
- `devShells`
- supporting `packages`

These outputs are secondary to the Den model, but they make the unified repo
operable without an additional wrapper flake.
