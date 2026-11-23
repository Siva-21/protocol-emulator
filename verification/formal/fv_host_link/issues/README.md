# host_link formal issues

One subfolder per issue, kept in git as evidence, with the failing waves:

```
issues/<issue_name>/
  trace.vcd           counterexample from run/fv_host_link_<task>/engine_0/trace[_<n>].vcd
                      (or trace<N>.vcd for a cover); *.fst also accepted
  trace.yw            Yosys witness of the same trace (optional, for replay)
  sby_<task>.log      the part of the sby log that shows the failure (optional)
  ast_<PROP_ID>.gtkw  GTKWave save file with the signals that explain the failure
  notes.md            see below
```

- `<issue_name>` is a short snake_case name of the issue (e.g.
  `miso_changes_before_sck_fall`), not of the property: one issue can fail
  several properties. The property ID and run date go in `notes.md`.
- Copy the trace out of `run/`: everything in `run/` is overwritten by the next
  `sby -f` and is git-ignored. Waveforms (`*.vcd`, `*.fst`) and logs are tracked
  only inside `fv_*/issues/`.

`notes.md`:

| Field | Content |
|---|---|
| Property | ID, `file:line`, the statement as written |
| sby task / step | task (`bmc`, `prove`, `cover`), failing step, engine, depth; commit hash of the RTL and props |
| Root cause | what the trace shows, clock by clock |
| Fault | RTL, property / assumption, or spec |
| Resolution | the fix (commit), the property change, or the spec question; GitHub issue link |
