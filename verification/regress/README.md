# Regressions (to come)

Runner and manifest for running the verification flows together:

- **manifest**: which unit tests, formal jobs and block checks make up a
  regression (e.g. per block, smoke vs. full).
- **runner**: runs the manifest entries in parallel inside `pe-verif` and writes
  a summary to `verification/reports/` (git-ignored).

Not implemented yet; until then run the flows one by one, see
[../README.md](../README.md).
