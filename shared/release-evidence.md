# release-evidence.md

A hand-maintained evidence index that joins observations across native run,
source, package and deployment views. Some platform links are built in; this
complete comparison is recorded by hand only after you observe it. Keep this file **outside**
the `orders-api` repository so editing it never adds a commit or changes the
revision you are recording.

Rules:

- `pending` is the only allowed placeholder. Never type a planned or guessed value.
- Section A (PR validation run), Section B (post-merge CI run) and Section C
  (release run) are **three different runs with three different run IDs**. Never
  copy one section's run ID, revision or artifact into another. The index joins
  nothing by name; each entry holds only what that run itself shows.
- A package, artifact or deployment reference is filled in only after you open it
  in the portal. A planned target is not deployment evidence.
- From the learner root, check the file with:
  `python3 module-01-setting-up-traceable-delivery/scripts/check-evidence.py shared/release-evidence.md`.
  Windows PowerShell uses the same arguments with `python` instead of `python3`;
  see [Windows setup](../README.md#setup). For an external working copy,
  replace the last argument with that file's quoted path.

Work item: `128` (synthetic placeholder; replace with your real work item ID before hosted practice)

## A. Pull request validation run (Module 1)

The `orders-api-ci` build that branch policy queues against the pull request's merge
result before completion. Keep every field `pending` until you observe it.

- Pipeline: `orders-api-ci`
- Pull request: pending
- Run ID: pending
- Revision (full 40-character commit ID): pending
- Result: pending
- Evidence read from: pending

## B. Post-merge CI run (Module 1)

Build-only run that `main` CI starts after the pull request is completed. It proves
what landed on `main`. It is not a release.

- Pipeline: `orders-api-ci`
- Source branch: `main`
- Pull request: pending
- Run ID: pending
- Revision (full 40-character commit ID): pending
- Result: pending
- Evidence read from: pending

## C. Release run (opt-in; Modules 2 and 3)

The manually queued run with `publishPackages` and/or `deployStaging` turned on.
Module 1 does not create it, so every field stays `pending` here.

- Pipeline: `orders-api-ci`
- Source branch: `main`
- Parameters: pending
- Run ID: pending
- Revision (full 40-character commit ID): pending
- Package (`Globomantics.Orders.Contracts`) version: pending
- Artifact (`orders-api-web`): pending
- Deployment (`staging` environment history): pending
