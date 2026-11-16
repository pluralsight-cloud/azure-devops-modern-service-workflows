# Module 1 — Setting up traceable delivery

This folder holds the one application the whole course uses, `orders-api`, and
the checks that prove it builds the same way locally and in a pipeline.

1. `orders-api/` is the sample service: a minimal .NET 10 API (`src/Orders.Api`),
   a contracts library packed as `Globomantics.Orders.Contracts`
   (`src/Orders.Contracts`), a small check program (`tests/Orders.Checks`), the
   pipeline entry point `azure-pipelines.yml` (`orders-api-ci`) and the shared
   build template `ci/build-stage.yml`.
2. `orders-api/ci/build.sh` and `ci/build.ps1` run the same restore, build,
   check, publish and pack steps as the pipeline, and write
   `out/web/release-evidence.txt`.
3. `scripts/01-local-smoke.sh` and `.ps1` run four checks: the happy path, the
   stale-output guard, an intentionally broken check, and a clean-agent build
   with an empty package cache.
4. `scripts/check-yaml.py` validates the pipeline YAML shape;
   `scripts/check-evidence.py` validates `../shared/release-evidence.md`.
5. `requirements.txt` installs PyYAML for the Python checks; `.env.example`
   lists the optional, non-secret build values.

Follow [runbook.md](runbook.md) for the commands, prerequisites, expected
output, hosted steps and cleanup. Complete the [repository setup](../README.md#setup)
first.
