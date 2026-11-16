# Module 2 — Walking through the pipeline

This module uses the Module 1 `orders-api` sample unchanged and adds tools to
walk through a passing run, a failing check and a duplicate package version.

1. `scripts/02-local-checks.sh` and `.ps1` run five checks: the pipeline gates,
   a corrected build, a copy with one failing assertion, a copy that repeats a
   package version, and the shape of `../shared/release-evidence.md`.
2. `scripts/prepare-practice-copy.sh` and `.ps1` create a throwaway copy of
   `orders-api` for one scenario (`corrected`, `failing` or `duplicate`) and
   print how it differs from the sample. They never change the sample, use the
   network or push anything.
3. `.env.example` lists the optional, non-secret build values (same as
   Module 1).

Follow [runbook.md](runbook.md) for the commands, prerequisites, expected
output, hosted steps and cleanup. Complete the [repository setup](../README.md#setup)
first.
