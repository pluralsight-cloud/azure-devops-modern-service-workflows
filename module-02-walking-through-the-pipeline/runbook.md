# Module 2 runbook — Walking through the pipeline

You read the pipeline stage by stage, reproduce a passing build, a failing
check and a duplicate package version locally, and then, optionally, publish
the contracts package to your own Azure Artifacts feed.

## Prerequisites and start state

- Complete the [repository setup](../README.md#setup) and
  [Module 1](../module-01-setting-up-traceable-delivery/runbook.md), Part A.
- Open a terminal in this folder, `module-02-walking-through-the-pipeline/`.
- The pipeline is `../module-01-setting-up-traceable-delivery/orders-api/azure-pipelines.yml`,
  and its build stage is `ci/build-stage.yml` in the same folder.
- For the hosted part only: the Module 1 pipeline running in your own project,
  with names replaced by [set-my-names](../README.md#use-your-own-names).

## Part A — Local (free)

### 1. Read the pipeline gates

Open `azure-pipelines.yml` and `ci/build-stage.yml`. Note three facts:

- Both parameters, `publishPackages` and `deployStaging`, default to `false`.
- The package version is `1.0.$(Build.BuildId)`, so every run gets a new one.
- The push step runs only when `publishPackages` is on **and** the branch is
  `main`.

### 2. Run the Module 2 checks

Bash:

```bash
bash scripts/02-local-checks.sh
```

PowerShell:

```powershell
pwsh scripts/02-local-checks.ps1
```

The script works in temporary folders and never changes the sample. Expect each
check `M2-1` to `M2-5` to report `ok`, this expected line:

```text
NOT PROVEN LOCALLY: Azure Artifacts HTTP 409 for a duplicate (a local folder feed overwrites silently).
```

and, at the end:

```text
ALL MODULE 2 LOCAL CHECKS PASSED
```

The `NOT PROVEN LOCALLY` line is not a failure. Only a real feed rejects a
repeated version; Part B shows it.

### 3. Prepare a practice copy

Create a copy for one scenario in a new, empty folder:

```bash
bash scripts/prepare-practice-copy.sh failing ~/orders-api-failing
```

PowerShell:

```powershell
pwsh scripts/prepare-practice-copy.ps1 failing ~/orders-api-failing
```

Expect `Prepared 'failing' copy in: …` and a diff with one changed line in
`tests/Orders.Checks/Program.cs`, from `"ready"` to `"shipped"`. Build the copy
with `bash ci/build.sh` from inside it; expect a `FAIL:` line, exit code 1 and
no package in `out/packages/`.

The scenarios are:

| Scenario | What changes | What you see in a run |
|---|---|---|
| `corrected` | Nothing (only the feed URL, if set) | The check passes and the package is pushed. |
| `failing` | One assertion | The build step fails; nothing is published or pushed. |
| `duplicate` | The version is pinned to `1.0.<build-id>` | The push is rejected because the feed already holds that version. |

`duplicate` needs the numeric Build ID of a run that already pushed a package:

```bash
bash scripts/prepare-practice-copy.sh duplicate ~/orders-api-duplicate 1234
```

If you omit it, the script stops with `STOP: duplicate needs the numeric Build ID …`
and changes nothing. If the target folder is not empty, it stops with exit 2.

## Part B — Hosted in your Azure DevOps project (optional)

### 1. Create the feed

In **Artifacts**, select **Create Feed**. Use the feed name you gave
`set-my-names` (the sample uses `globomantics-packages`) and **Project** scope.

### 2. Let the pipeline publish

In the feed's **Feed settings > Permissions**, add
`<your project> Build Service (<your organization>)` with the
**Feed Publisher (Contributor)** role. Without it, the push fails with
HTTP 403.

### 3. Run with publishing on

Run `orders-api-ci` from `main` with `publishPackages` on and `deployStaging`
off.

Expect the **Build** stage to succeed with an extra step,
**Publish contracts to …**, and the feed to list
`Globomantics.Orders.Contracts` version `1.0.<run ID>`. Note the run ID; you
need it for the duplicate scenario.

### 4. Practice the failing and duplicate runs (use a disposable project)

The push runs only from `main`, so a practice copy must be the `main` branch of
its own repository. Use a separate, disposable project and feed:

1. Create a practice project and a project-scoped practice feed, and give its
   build service Feed Publisher (Contributor), as in steps 1–2.
2. Set the practice feed URL before you prepare each copy:

   ```bash
   export PRACTICE_FEED_URL="https://pkgs.dev.azure.com/<org>/<practice-project>/_packaging/<practice-feed>/nuget/v3/index.json"
   ```

   PowerShell: `$env:PRACTICE_FEED_URL = "https://…/nuget/v3/index.json"`.
   Without it, the script warns that the copy pushes to the feed in
   `ci/build-stage.yml`.
3. Push the copy as `main` of a repository in the practice project, create a
   pipeline from its `azure-pipelines.yml` and run it with `publishPackages` on.

Expect:

- `failing`: the **Build validate publish and pack** step fails with
  `FAIL: positive order contract`; no artifact or package is published.
- `duplicate`: the build succeeds but the push fails with HTTP 409 (conflict),
  because the version already exists.

Package versions are immutable. A deleted version stays in the feed's Recycle
Bin for 30 days and still cannot be pushed again, which is why the practice
feed should be disposable.

### 5. Record the release run (optional)

Copy only what the run and feed pages show into section C of
`../shared/release-evidence.md`, then rerun the evidence check from the
[Module 1 runbook](../module-01-setting-up-traceable-delivery/runbook.md#5-check-the-evidence-index).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Push returns 401 | `NuGetAuthenticate@1` did not run or the feed URL is wrong; rerun `set-my-names`. |
| Push returns 403 | The build service lacks Feed Publisher (Contributor) on the feed. |
| Push returns 409 | The version already exists; run again for a new Build ID. |
| Push step is skipped | `publishPackages` is off or the run is not on `main`. |

## Clean up

- Local: delete the practice-copy folders you created.
- Hosted: delete the practice project (its feed goes with it). Keep the main
  project's feed if you continue to Module 3.
