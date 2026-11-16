# Module 1 runbook — Setting up traceable delivery

You build `orders-api` locally exactly as the pipeline does, prove that a
broken check stops the build, and then, optionally, run the same pipeline in
your own Azure DevOps project as a build-only run.

## Prerequisites and start state

- Complete the [repository setup](../README.md#setup): .NET SDK 10.0.403,
  Python 3.9+ with PyYAML 6.0.3, and Bash or PowerShell 7.
- Open a terminal in this folder, `module-01-setting-up-traceable-delivery/`.
- Make sure `orders-api/out/` does not exist. The build stops rather than
  overwrite an earlier output.
- For the hosted part only: your own Azure DevOps organization and project, and
  the names replaced with [set-my-names](../README.md#use-your-own-names).

The build reads three optional values. None is a secret:

| Variable | Default | In the pipeline |
|---|---|---|
| `PACKAGE_VERSION` | `1.0.0-local` | `1.0.$(Build.BuildId)` |
| `RUN_ID` | `local` | `$(Build.BuildId)` |
| `SOURCE_REVISION` | `unrecorded-local` | `$(Build.SourceVersion)` |

## Part A — Local (free)

### 1. Confirm the pinned SDK

```bash
cd orders-api
dotnet --version
```

Expect `10.0.403`. `global.json` disables roll-forward, so any other SDK stops
here with an error naming the required version.

### 2. Build the app once by hand

Bash:

```bash
bash ci/build.sh
```

PowerShell:

```powershell
pwsh ci/build.ps1
```

Expect `PASS: positive order and invalid-ID checks` from the check program,
followed by the evidence lines:

```text
workload=orders-api
run_id=local
source_revision=unrecorded-local
package_version=1.0.0-local
```

The web output is in `out/web/` and the package
`Globomantics.Orders.Contracts.1.0.0-local.nupkg` is in `out/packages/`.

### 3. See the stale-output guard

Run the build a second time without removing `out/`.

Expect `STOP: out already exists; inspect and remove only generated output before retry.`
and exit code 2. Remove only the generated folder, then return to the module
folder:

```bash
rm -rf out        # PowerShell: Remove-Item -Recurse -Force out
cd ..
```

### 4. Run the smoke checks

Bash:

```bash
bash scripts/01-local-smoke.sh
```

PowerShell:

```powershell
pwsh scripts/01-local-smoke.ps1
```

The script works in a temporary copy and never changes `orders-api/`. It runs:

1. the happy path with pipeline-style values;
2. the stale-output guard (exit 2);
3. one changed assertion, which must fail with exit 1 and produce no package;
4. a clean-agent build with an empty NuGet cache and CLI home.

Expect the run to end with:

```text
SMOKE-4 ok: cold cache builds; evidence version equals package version; no third-party packages restored
ALL SMOKE CHECKS PASSED
```

If the first run is slow, `dotnet restore` is filling your local package cache
from nuget.org; run the script again once it completes.

### 5. Check the evidence index

From the repository root:

```bash
python3 module-01-setting-up-traceable-delivery/scripts/check-evidence.py shared/release-evidence.md
```

On Windows, use `python` instead of `python3`. Expect
`PASS: evidence index shape and run separation` while every field is still
`pending`.

## Part B — Hosted in your Azure DevOps project (optional)

### 1. Replace the account-bound names

From the repository root, run `set-my-names` with your organization, project,
feed and app names. See [Use your own names](../README.md#use-your-own-names).

### 2. Push the app to Azure Repos

Create a Git repository in your project. Push the **contents** of
`orders-api/` (not this whole folder) as the repository root on branch `main`:

```bash
cd orders-api
git init -b main
git add .
git commit -m "Add orders-api"
git remote add origin https://dev.azure.com/<your-org>/<your-project>/_git/<your-repo>
git push -u origin main
```

Expect `azure-pipelines.yml`, `ci/`, `src/`, `tests/` and `global.json` at the
root of the repository in the web portal.

### 3. Create the pipeline

In **Pipelines**, create a new pipeline from **Azure Repos Git**, select your
repository and choose **Existing Azure Pipelines YAML file** with path
`/azure-pipelines.yml`. Save it and rename it `orders-api-ci`.

### 4. Add branch policies (optional)

In **Repos > Branches**, open the policies for `main`. Add **Build validation**
with `orders-api-ci` and, if you want traceability, **Check for linked work
items**. Pull request validation comes from this policy, not from the YAML.

### 5. Run a build-only pipeline

Select **Run pipeline**, leave `publishPackages` and `deployStaging` off, and
run from `main`.

Expect one **Build** stage that succeeds and publishes the `orders-api-web`
artifact. There is no package push and no Staging stage. The run summary shows
the run ID and the full commit ID; the evidence lines in the log use them.

### 6. Fill the evidence index (optional)

If you completed a pull request through the build validation policy, copy the
pull request run into section A and the post-merge `main` run into section B of
`shared/release-evidence.md`. Copy values only after you see them in the portal,
then run the evidence check from Part A, step 5 again.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `A compatible .NET SDK was not found` | Install SDK 10.0.403 exactly. |
| `STOP: out already exists` | Remove `orders-api/out/`, then rerun. |
| `ModuleNotFoundError: No module named 'yaml'` | Install `requirements.txt` with the same Python you run. |
| Pipeline asks to authorize a resource | Approve it in the run page; only Modules 2–3 use the feed and service connection. |

## Clean up

- Local: the smoke script deletes its temporary folders. Delete
  `orders-api/out/` if you built by hand.
- Hosted: keep the project and pipeline if you continue to Module 2.
  Otherwise delete the Azure DevOps project.
