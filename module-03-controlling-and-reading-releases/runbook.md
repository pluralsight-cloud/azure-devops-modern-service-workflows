# Module 3 runbook — Controlling and reading releases

You check the `Staging` stage definition, run the app locally to read its
release evidence, and then, optionally, deploy it to your own App Service
behind an approval.

## Prerequisites and start state

- Complete the [repository setup](../README.md#setup) and
  [Module 1](../module-01-setting-up-traceable-delivery/runbook.md), Part A.
- Bash users also need `curl`.
- Open a terminal in this folder, `module-03-controlling-and-reading-releases/`.
- The `Staging` stage is in
  `../module-01-setting-up-traceable-delivery/orders-api/azure-pipelines.yml`.
- For the hosted part only: the Module 1 pipeline running in your own project
  and an Azure subscription. The hosted part creates Azure resources that may
  cost money.

## Part A — Local (free)

### 1. Read the Staging stage

Open `azure-pipelines.yml` and find `stage: Staging`. Note that:

- It exists only when `deployStaging` is on, and runs only after `Build`
  succeeds on `main`.
- It is a deployment job, `DeployOrders`, that targets the environment
  `staging`. Approvals are set on that environment, not in the YAML.
- It downloads the `orders-api-web` artifact from the same run and deploys it
  with `AzureWebApp@1`, using the service connection in `azureSubscription` and
  the app in `appName`.

### 2. Run the Module 3 checks

Bash:

```bash
bash scripts/03-local-checks.sh
```

PowerShell:

```powershell
pwsh scripts/03-local-checks.ps1
```

The script builds in a temporary folder, starts the app on a free local port
(`127.0.0.1`) and stops it afterwards. Expect checks `M3-1` to `M3-5` to report
`ok`, including:

```text
M3-3 ok: /release is plain text with four lines; /health is {"status":"ok"}; /orders/42 is {"id":42,"status":"ready"}
M3-4 ok: HTTP 404 without release-evidence.txt
```

then this expected line:

```text
NOT PROVEN LOCALLY: Azure DevOps approval, rejection, timeout, deployment history, App Service runtime, service connection, tenant UI labels.
```

and, at the end:

```text
ALL MODULE 3 LOCAL CHECKS PASSED
```

The `/release` endpoint returns the four lines the build wrote:
`workload=orders-api`, `run_id=…`, `source_revision=…` and
`package_version=…`. That is how you match a running app to the run that built
it.

## Part B — Hosted in Azure and Azure DevOps (optional, may cost money)

Use names you chose with [set-my-names](../README.md#use-your-own-names). The
App Service name must be globally unique.

### 1. Create the App Service

In the Azure portal, create a resource group and a **Web App** with:

- **Publish**: Code
- **Runtime stack**: .NET 10
- **Operating system**: Linux
- **Pricing plan**: Free F1 is enough

Expect the app's default page at `https://<your-app>.azurewebsites.net`.

### 2. Create the service connection

In Azure DevOps, go to **Project settings > Service connections > New service
connection > Azure Resource Manager**. Choose **Workload identity federation
(automatic)**, your subscription and the resource group from step 1, and use
the service connection name you gave `set-my-names`.

Expect the connection in the list, with no secret to store.

### 3. Create the staging environment and approval

Go to **Pipelines > Environments > New environment**, name it `staging` and
select **None** for the resource. Open it, then **Approvals and checks > +
Approvals**, add yourself as an approver and save.

### 4. Run a release

Run `orders-api-ci` from `main` with `deployStaging` on. Turn on
`publishPackages` too if you completed Module 2's feed setup.

Expect `Build` to succeed and `Staging` to wait for approval. Open the waiting
stage, select **Review > Approve**. Expect `DeployOrders` to succeed.

Then read the app:

```bash
curl https://<your-app>.azurewebsites.net/release
```

PowerShell:

```powershell
Invoke-RestMethod https://<your-app>.azurewebsites.net/release
```

Expect four lines whose `run_id` is the run you just approved and whose
`source_revision` is that run's commit.

Optionally, run again and select **Reject**. Expect `Staging` to fail without
deploying, and `/release` to still show the earlier run.

### 5. Record the release run

In **Pipelines > Environments > staging**, open the deployment history. Copy
only what the run page, environment history and `/release` show into section C
of `../shared/release-evidence.md`. Then run the evidence check from the
repository root:

```bash
python3 module-01-setting-up-traceable-delivery/scripts/check-evidence.py shared/release-evidence.md
```

Expect `PASS: evidence index shape and run separation`.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Staging` does not appear | `deployStaging` is off, or the run is not on `main`. |
| "Service connection could not be found" | The `azureSubscription` name does not match your connection; rerun `set-my-names`, or authorize the connection for the pipeline when prompted. |
| Deployment fails with "resource not found" | `appName` does not match your App Service, or the connection is scoped to another resource group. |
| `Staging` is skipped after waiting | Nobody approved before the approval's own timeout (set on the check). Run again. |
| `DeployOrders` times out | The deployment job itself is capped at 15 minutes; check the App Service and rerun. |
| `/release` returns 404 | The deployed package has no `release-evidence.txt`; deploy an artifact built by `ci/build.sh`. |

## Clean up

- Local: nothing to clean; the script removes its temporary folder.
- Hosted: delete the resource group (this removes the App Service), then delete
  the service connection and the `staging` environment if you no longer need
  them.
