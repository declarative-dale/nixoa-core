# Getting Started

This guide begins after NiXOA is installed. If you still need to create the
appliance, start with [Installation](installation.md).

## 1. Connect

Find the VM address in XCP-ng or Xen Orchestra, then connect with the SSH key
used during installation:

```bash
ssh nixoa@<vm-address>
```

The appliance uses SSH-key authentication for the `nixoa` operator.

## 2. Open Xen Orchestra

Visit:

```text
https://<vm-address>/
```

NiXOA creates a self-signed certificate by default, so your browser will show a
warning on the first visit. You can replace the certificate later.

## 3. Check the appliance

```bash
nxcli status
nxcli xo logs
```

For a guided interface, run:

```bash
nixoa-menu
```

## 4. Make a safe change

Use `nixoa-menu`, or edit the durable configuration:

```bash
nxcli host edit
```

Then review and preview the change before activating it:

```bash
nxcli diff
nxcli apply --dry-run
nxcli apply
```

If the new generation causes a problem:

```bash
nxcli rollback --ask
```

## Next steps

- [Common tasks](common-tasks.md) for SSH keys, packages, TLS, and storage
- [Operations](operations.md) for updates, boot generations, and logs
- [Troubleshooting](troubleshooting.md) for symptom-based checks and recovery

[Back to documentation](index.md)
