# Module 3 — Controlling and reading releases

This module uses the Module 1 `orders-api` sample and its optional `Staging`
stage. It shows how to gate a release with an approval and how to read what is
running from the app itself.

1. `scripts/03-local-checks.sh` and `.ps1` run five checks: the `Staging` stage
   definition, a build that writes `release-evidence.txt`, the app's
   `/release`, `/health` and `/orders/42` endpoints on your machine, the 404 when
   no evidence file exists, and the release section of
   `../shared/release-evidence.md`.
2. `.env.example` lists the optional, non-secret build values (same as
   Modules 1 and 2).

Follow [runbook.md](runbook.md) for the commands, prerequisites, expected
output, hosted steps and cleanup. Complete the [repository setup](../README.md#setup)
first.
