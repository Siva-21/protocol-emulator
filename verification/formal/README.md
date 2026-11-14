# Formal (SymbiYosys)

Per-block formal proofs, one directory per block:

```
formal/<block>/
  <block>.sby          SymbiYosys job: RTL from src/<block>/<block>.f + the property files
  <block>_props.sv     properties (assert / assume / cover), bound to <block>
```

- Run from the block's folder (sby resolves `[files]` against the current
  directory): `cd verification/formal/<block> && sby -f <block>.sby`.
  Template and steps: [docs/WORKFLOWS.md](../../docs/WORKFLOWS.md#formal-with-sby).
- Engines available in `pe-verif`: yices (default), bitwuzla, z3 for
  `smtbmc`; `abc pdr` for unbounded proofs. Read RTL and properties with
  `read_slang` and attach the properties with `bind`.
- Properties stay out of `src/`: the RTL that gets hardened has no formal-only code.
- sby work directories (`<block>_<task>/`) are git-ignored.
