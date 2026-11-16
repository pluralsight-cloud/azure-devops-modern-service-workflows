# Module 4 — Troubleshooting from evidence

This module reproduces common pipeline failures so you can tell them apart by
their evidence. It also includes a GitHub Actions version of the same build for
comparison.

1. `scripts/04-local-checks.sh` and `.ps1` run seven checks: the workflow
   structure; a YAML error compared with a structure mistake; a re-run attempt;
   a compiler error compared with a failing check; authentication, permission
   and duplicate-version errors from a local mock feed; a deploy path mismatch;
   and the deploy job's own checks, with no sign-in and no deployment.
2. `scripts/check-workflow.py` checks the workflow file's structure and safety
   rules and names the rule that fails.
3. `scripts/mock-feed.py` is a local stand-in for a package feed that returns
   401, 403 or 409. It never contacts a real feed.
4. `workflows/orders-api-github.yml` builds the Module 1 sample with GitHub
   Actions. Publishing and deployment are optional and off by default.
5. `.env.example` shows example values; Module 4 needs no variables or secrets
   from you.

Follow [runbook.md](runbook.md) for the commands, prerequisites, expected
output, hosted steps and cleanup. Complete the [repository setup](../README.md#setup)
first.
