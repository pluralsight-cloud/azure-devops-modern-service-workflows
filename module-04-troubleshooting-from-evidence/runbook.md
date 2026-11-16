# Module 4 runbook — Troubleshooting from evidence

You reproduce each failure class locally and read the evidence that tells them
apart. Then, optionally, you run the same build with GitHub Actions in your own
repository.

## Prerequisites and start state

- Complete the [repository setup](../README.md#setup) and
  [Module 1](../module-01-setting-up-traceable-delivery/runbook.md), Part A.
- Open a terminal in this folder, `module-04-troubleshooting-from-evidence/`.
- For the hosted part only: a GitHub account. Deployment also needs an Azure
  subscription and may cost money.

## Part A — Local (free)

### 1. Run the Module 4 checks

Bash:

```bash
bash scripts/04-local-checks.sh
```

PowerShell:

```powershell
pwsh scripts/04-local-checks.ps1
```

Everything runs in temporary folders. Expect checks `M4-1` to `M4-7` to report
`ok`, and, at the end:

```text
ALL MODULE 4 LOCAL CHECKS PASSED
```

Each check line says what was and was not exercised. Read them as the evidence
for each failure class:

| Check | Failure class | Evidence that identifies it |
|---|---|---|
| M4-2 | YAML error vs structure mistake | A file that cannot be parsed exits 2; a valid file that breaks a rule exits 1 and names the rule. |
| M4-3 | Re-run | The run number stays the same and the attempt increases, so each attempt builds a different package version. |
| M4-4 | Build vs check failure | A compiler error stops before the check runs; a failing check prints `FAIL:` after a successful compile. |
| M4-5 | Feed errors | 401 is authentication, 403 is permission, 409 is a duplicate version. Recover from 409 with a new version, not a delete. |
| M4-6 | Deploy path mismatch | The deploy step's package path must match the folder the artifact was downloaded to. |
| M4-7 | Missing deploy settings | A missing variable stops the deploy job before it signs in. |

### 2. Check the workflow on its own

From this folder:

```bash
python3 scripts/check-workflow.py workflows/orders-api-github.yml
```

On Windows, use `python` instead of `python3`. Expect:

```text
ALL WORKFLOW STRUCTURE CHECKS PASSED (file-only; GitHub has not parsed it)
```

Change a line, for example remove a `timeout-minutes:`, and run it again.
Expect exit code 1 and a message naming the broken rule. Undo the change.

### 3. Try the mock feed (optional)

The check script already starts the mock feed for you. To push to it yourself,
start it in one terminal with the status code to return and a port:

```bash
python3 scripts/mock-feed.py 409 5555
```

In a second terminal, push the package from a Module 1 local build. If
`orders-api/out/packages/` does not exist, run the build from the
[Module 1 runbook](../module-01-setting-up-traceable-delivery/runbook.md) first.

```bash
dotnet nuget push ../module-01-setting-up-traceable-delivery/orders-api/out/packages/*.nupkg \
  --source http://127.0.0.1:5555/index.json --api-key local-only \
  --allow-insecure-connections
```

`--allow-insecure-connections` is needed only because the mock feed uses plain
HTTP on your own machine. Never use it with a real feed. Stop the mock feed
with Ctrl+C when you are done, and remove `orders-api/out/` afterwards.

Expect the push to fail with a 409 conflict. Restart the mock feed with `401` or
`403` and compare the messages. It listens only on `127.0.0.1`.

## Part B — Hosted with GitHub Actions (optional)

### 1. Create your repository

Create a new GitHub repository that you own. Copy the **contents** of
`../module-01-setting-up-traceable-delivery/orders-api/` to its root, so
`ci/build.sh` is at the top level. Then copy
`workflows/orders-api-github.yml` to `.github/workflows/orders-api-github.yml`
and push to `main`.

### 2. Run a build

In **Actions**, select **orders-api-github > Run workflow** on `main` with both
inputs off.

Expect the `build` job to succeed, the run summary to show the
`release evidence` lines, and two artifacts: `orders-api-web` and
`orders-api-contracts`. The package version is `1.0.<run number>-attempt.1`.

Select **Re-run jobs**. Expect the same run number with `-attempt.2`.

### 3. Publish to GitHub Packages (optional)

Run again with `publishPackages` on. The job uses the run's built-in
`GITHUB_TOKEN`; you add no secret. Expect `Globomantics.Orders.Contracts` under
your account's or organization's **Packages**. Re-running that job pushes the
same version again, so expect it to fail with a conflict.

### 4. Deploy to Azure (optional, may cost money)

This needs the App Service from the
[Module 3 runbook](../module-03-controlling-and-reading-releases/runbook.md#1-create-the-app-service),
or one like it, plus:

1. A Microsoft Entra app registration (or user-assigned managed identity) with
   a federated credential for your repository and the `staging` environment
   (subject `repo:<owner>/<repo>:environment:staging`).
2. A role on the App Service for that identity, such as Website Contributor.
3. A GitHub environment named `staging`, with required reviewers if your plan
   supports them.
4. Repository variables (not secrets): `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID` and `AZURE_WEBAPP_NAME`.

Run the workflow with `deployStaging` on. Expect `deploy-staging` to wait for
review (if set), then sign in with OIDC and deploy. Read
`https://<your-app>.azurewebsites.net/release` and compare it with the build
summary.

If a variable is missing, expect the job to stop at its first step with
`STOP: owner-provided variable(s) not set: …`.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `bash: ci/build.sh: No such file or directory` | The repository root is not the contents of `orders-api`. |
| `AADSTS700213` or "no matching federated identity" | The federated credential subject does not match the repository and environment. |
| Push returns 403 | The job lacks `packages: write`, or the package belongs to another repository; check the package's access settings. |
| Push returns 409 | The version already exists; run the workflow again for a new run number. |

## Clean up

- Local: nothing to clean; the scripts remove their temporary folders.
- Hosted: delete your practice repository, its packages, and any Entra app
  registration, role assignment or Azure resources you created.
