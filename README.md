# Azure DevOps for Modern Service Workflows

> Course URL:
> https://www.pluralsight.com/courses/azure-devops-modern-service-workflows

This repository holds everything you need to run the course examples on your own
machine and, if you choose, in your own Azure DevOps organization, Azure
subscription and GitHub account. It contains:

- one small .NET 10 service, `orders-api`, reused by every module;
- the Azure Pipelines YAML used in the course;
- a GitHub Actions workflow for comparison;
- one local check script per module, in Bash and PowerShell.

Each module folder has a short `README.md` and a step-by-step `runbook.md`.

## Two ways to follow along

| Path                            | What you need                                                                                                                         | Cost                                                                                                                                                                 | What it proves                                                            |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| **Local only** (start here)     | .NET SDK, Python, Bash or PowerShell 7                                                                                                | Free                                                                                                                                                                 | The sample builds, the checks pass, and the YAML and evidence rules hold. |
| **Hosted in your own accounts** | Your own Azure DevOps organization and project; for deployment, your own Azure subscription; for Module 4, your own GitHub repository | The Azure DevOps free tier covers 5 Basic users, one Microsoft-hosted parallel job (1,800 minutes/month) and 2 GiB of Artifacts storage. App Service can cost money. | The real pipeline, feed, approvals and deployment in your own tenant.     |

The local checks never call Azure DevOps, Azure or GitHub. They work in a
temporary copy and never change the files in this repository. The build runs
`dotnet restore`, so it may contact nuget.org unless the packages are already
cached.

## Use your own names

The sample uses fictional Globomantics names. Five of them refer to accounts and
resources, so you must replace them with names you own before any hosted run:

| Sample name                    | What it is                                | Where it appears                             | Yours must be                                                         |
| ------------------------------ | ----------------------------------------- | -------------------------------------------- | --------------------------------------------------------------------- |
| `globomantics-devops`          | Azure DevOps organization                 | Feed URL in `ci/build-stage.yml`             | An organization you own                                               |
| `globomantics-orders`          | Azure DevOps project                      | Feed URL in `ci/build-stage.yml`             | A project in that organization                                        |
| `globomantics-packages`        | Azure Artifacts feed                      | Feed URL in `ci/build-stage.yml`             | A project-scoped feed you create                                      |
| `app-globomantics-orders-stg`  | Azure App Service (Linux)                 | `appName` in `azure-pipelines.yml`           | **Globally unique**, for example `app-orders-<initials>-<number>`     |
| `sc-globomantics-orders-azure` | Azure Resource Manager service connection | `azureSubscription` in `azure-pipelines.yml` | You may keep this name, but create the connection in your own project |

These names are part of the sample and stay as they are:
`Globomantics.Orders.Contracts` (package ID), `orders-api-ci` (pipeline),
`orders-api-web` and `orders-api-contracts` (artifacts), `staging` (environment)
and `orders-api-github` (workflow). Work item `128` in
`shared/release-evidence.md` is a placeholder; use an ID from your own board.

From the repository root, rewrite the five names in one step:

```bash
bash set-my-names.sh --org <your-org> --project <your-project> \
  --feed <your-feed> --app <your-unique-app-name> \
  [--service-connection <your-connection-name>]
```

```powershell
pwsh ./set-my-names.ps1 -Org <your-org> -Project <your-project> `
  -Feed <your-feed> -App <your-unique-app-name> `
  [-ServiceConnection <your-connection-name>]
```

The script edits only `azure-pipelines.yml` and `ci/build-stage.yml` in
`module-01-setting-up-traceable-delivery/orders-api/`. It checks the format of
every name first and changes nothing if any name is invalid. It cannot check
whether the names exist in Azure DevOps or Azure. You can run it again with
different values, and all local checks still pass afterwards.

> The comments near the deploy step in `azure-pipelines.yml` are reminders:
> confirm that your service connection and App Service exist before you turn on
> `deployStaging`.

## Setup

Install:

- **.NET SDK 10.0.403** exactly. `orders-api/global.json` pins this version and
  disables roll-forward, so another SDK fails with a clear message.
- **Python 3.9 or later**, then from the repository root:

  ```bash
  python3 -m pip install -r module-01-setting-up-traceable-delivery/requirements.txt
  ```

  This installs `PyYAML 6.0.3`. On Windows, use `python` instead of `python3`.

- **Bash** (macOS, Linux, WSL or Git Bash) **or PowerShell 7** (`pwsh`). Every
  check has a `.sh` and a `.ps1` version with the same behavior.
- **curl**, used only by the Bash Module 3 check.

Confirm your tools:

```bash
cd module-01-setting-up-traceable-delivery/orders-api
dotnet --version                                   # expect 10.0.403
python3 -c "import yaml; print(yaml.__version__)"  # expect 6.0.3
```

No credentials are stored in this repository. Each module's `.env.example` holds
only optional, non-secret values. Never commit a token or secret.

## Modules

Run each module's check from that module's folder. Every check prints an `ok` or
`PASS` line per step and ends with one `ALL ... PASSED` line. Lines that start
with `NOT PROVEN LOCALLY` name what only a hosted run can show; they are
expected. Any failure stops the script with a non-zero exit code.

| Module                               | Local check                           | Runbook                                                          |
| ------------------------------------ | ------------------------------------- | ---------------------------------------------------------------- |
| 1 — Setting up traceable delivery    | `scripts/01-local-smoke.sh` / `.ps1`  | [runbook](module-01-setting-up-traceable-delivery/runbook.md)    |
| 2 — Walking through the pipeline     | `scripts/02-local-checks.sh` / `.ps1` | [runbook](module-02-walking-through-the-pipeline/runbook.md)     |
| 3 — Controlling and reading releases | `scripts/03-local-checks.sh` / `.ps1` | [runbook](module-03-controlling-and-reading-releases/runbook.md) |
| 4 — Troubleshooting from evidence    | `scripts/04-local-checks.sh` / `.ps1` | [runbook](module-04-troubleshooting-from-evidence/runbook.md)    |

The modules build on each other: Module 1 sets up the app and pipeline, Module 2
walks through a run including the package push, Module 3 adds the staging
deployment and approval, and Module 4 troubleshoots failures and compares the
same delivery in GitHub Actions.

## Repository layout

```text
README.md                    this guide
set-my-names.sh / .ps1       replace the account-bound sample names
shared/
  release-evidence.md        evidence record used across modules
  LocalChecks.Common.ps1     helpers for the PowerShell checks
module-01-setting-up-traceable-delivery/
  orders-api/                the app, reused by every module
    azure-pipelines.yml      pipeline entry point (orders-api-ci)
    ci/build-stage.yml       build, check, artifact and optional package push
    ci/build.sh / build.ps1  the same build, runnable locally
  scripts/                   01-local-smoke, check-yaml.py, check-evidence.py
module-02-walking-through-the-pipeline/scripts/
  02-local-checks, prepare-practice-copy
module-03-controlling-and-reading-releases/scripts/
  03-local-checks
module-04-troubleshooting-from-evidence/
  workflows/orders-api-github.yml   GitHub Actions workflow
  scripts/                   04-local-checks, check-workflow.py, mock-feed.py
```

## Clean up

- **Local:** the checks use temporary folders. If you built by hand, delete
  `orders-api/out/`. `out/`, `bin/` and `obj/` are ignored by Git.
- **Hosted:** delete the App Service or its resource group to stop charges.
  Remove the service connection, federated credential and any practice feed you
  created. Published package versions cannot be reused, even after deletion.

## Verification status

| Check                                        | Level                                                                                  | Environment                                                                     |
| -------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Module 1–4 local checks, Bash and PowerShell | Run locally; each ends with `ALL ... PASSED`                                           | macOS, .NET 10.0.403, Python 3.9.6, PyYAML 6.0.3, bash 3.2.57, PowerShell 7.6.6 |
| `set-my-names`, both shells                  | Run locally; checks pass with sample and replaced names; invalid input changes nothing | same                                                                            |
| Hosted steps                                 | Depend on your own accounts; your run IDs, versions and times will differ              | —                                                                               |
