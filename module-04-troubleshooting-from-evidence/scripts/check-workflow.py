#!/usr/bin/env python3
"""Structural/safety check of the Module 4 GitHub workflow (no GitHub needed).

Usage: python3 check-workflow.py [path-to-workflow.yml]
Requires PyYAML (../../module-01-setting-up-traceable-delivery/requirements.txt).
This checks the FILE only. It is NOT GitHub's own workflow validation: only GitHub
parses and runs the workflow for real. Exit 0 = all checks ok, 1 = a check failed,
2 = the YAML could not be parsed (a YAML error, a different class from a failed check).
"""
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML missing: python3 -m pip install -r ../module-01-setting-up-traceable-delivery/requirements.txt")

default = Path(__file__).resolve().parent.parent / "workflows" / "orders-api-github.yml"
path = Path(sys.argv[1]) if len(sys.argv) > 1 else default
text = path.read_text(encoding="utf-8")
try:
    doc = yaml.safe_load(text)
except yaml.YAMLError as exc:
    print("YAML ERROR: " + str(exc).splitlines()[0] + " | " + " ".join(str(exc).split("\n")[1:3]))
    sys.exit(2)

failures = []


def expect(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)


# PyYAML (YAML 1.1) loads the bare key `on` as boolean True.
triggers = doc.get("on", doc.get(True))
jobs = doc.get("jobs", {})
build = jobs.get("build", {})
publish = jobs.get("publish-package", {})
deploy = jobs.get("deploy-staging", {})
steps_b = build.get("steps", [])
steps_p = publish.get("steps", [])
steps_d = deploy.get("steps", [])
steps_all = steps_b + steps_p + steps_d
uses = [s["uses"] for s in steps_all if "uses" in s]

expect(isinstance(triggers, dict) and list(triggers) == ["workflow_dispatch"], "only trigger is workflow_dispatch (no push/pull_request/schedule)")
inputs = (triggers or {}).get("workflow_dispatch", {}).get("inputs", {})
inp = inputs.get("publishPackages", {})
expect(inp.get("type") == "boolean" and inp.get("default") is False, "publishPackages is a boolean input defaulting to false (opt-in)")
dep_in = inputs.get("deployStaging", {})
expect(dep_in.get("type") == "boolean" and dep_in.get("default") is False, "deployStaging is a boolean input defaulting to false (opt-in)")
expect(doc.get("permissions") == {"contents": "read"}, "workflow-level permissions are exactly contents: read")
expect("permissions" not in build, "build job adds no permissions of its own (inherits contents: read)")
expect(publish.get("permissions") == {"contents": "read", "packages": "write"}, "publish-package has exactly contents: read + packages: write")
expect(sum(j.get("permissions", {}).get("packages") == "write" for j in jobs.values()) == 1 and "packages" not in doc.get("permissions", {}), "packages: write appears on exactly one job and not at workflow level")
expect(publish.get("needs") == "build", "publish-package needs build")
cond = str(publish.get("if", ""))
expect("inputs.publishPackages" in cond and "refs/heads/main" in cond, "publish-package runs only when opted in and on main")
# --- optional Azure deployment extension (explicit opt-in; OIDC identity separate from GITHUB_TOKEN) ---
dcond = str(deploy.get("if", ""))
expect(deploy.get("permissions") == {"contents": "read", "id-token": "write"}, "deploy-staging has exactly contents: read + id-token: write (no packages)")
expect(sum(j.get("permissions", {}).get("id-token") == "write" for j in jobs.values()) == 1 and not any("id-token" in p for p in [doc.get("permissions", {}), build.get("permissions", {}), publish.get("permissions", {})]), "id-token: write appears only on deploy-staging")
expect(set(deploy.get("needs", [])) == {"build", "publish-package"} and isinstance(deploy.get("needs"), list), "deploy-staging needs build and publish-package")
expect("inputs.deployStaging" in dcond and "refs/heads/main" in dcond and "!cancelled()" in dcond and "needs.build.result == 'success'" in dcond, "deploy-staging runs only when opted in, on main, not cancelled, and after a successful build")
expect("needs.publish-package.result == 'success'" in dcond and "needs.publish-package.result == 'skipped'" in dcond and "failure" not in dcond, "deploy-staging accepts a successful or skipped package job, never a failed one")
expect(deploy.get("environment") == {"name": "staging"}, "deploy-staging targets environment staging (reviewers are owner-configured, not asserted here)")
expect(deploy.get("concurrency") == {"group": "orders-api-staging", "cancel-in-progress": False}, "deploy concurrency group orders-api-staging with cancel-in-progress: false")
first = steps_d[0] if steps_d else {}
login_idx = next((i for i, s in enumerate(steps_d) if str(s.get("uses", "")).startswith("azure/login")), -1)
expect(login_idx > 0 and "AZURE_CLIENT_ID" in first.get("run", "") and "AZURE_WEBAPP_NAME" in first.get("run", "") and "exit 1" in first.get("run", ""), "the first deploy step stops early on a missing owner variable, before any login")
dl = next((s for s in steps_d if str(s.get("uses", "")).startswith("actions/download-artifact")), {})
dep = next((s for s in steps_d if str(s.get("uses", "")).startswith("azure/webapps-deploy")), {})
expect(dl.get("with", {}).get("name") == "orders-api-web" and dl.get("with", {}).get("path") == dep.get("with", {}).get("package") == "${{ runner.temp }}/orders-api-web", "deploy downloads orders-api-web and deploys exactly that folder")
login = next((s for s in steps_d if str(s.get("uses", "")).startswith("azure/login")), {})
expect(set(login.get("with", {})) == {"client-id", "tenant-id", "subscription-id"} and all(str(v).startswith("${{ vars.AZURE_") for v in login.get("with", {}).values()), "azure/login uses only owner variables for client/tenant/subscription ID (no creds, no secret, no literal)")
expect(str(dep.get("with", {}).get("app-name")) == "${{ vars.AZURE_WEBAPP_NAME }}" and "publish-profile" not in dep.get("with", {}), "webapps-deploy takes the app name from an owner variable and no publish profile")
expect(set(re.findall(r"vars\.([A-Za-z_]+)", text)) == {"AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID", "AZURE_WEBAPP_NAME"}, "only the four owner variables are referenced")
expect(not re.search(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", text) and "client-secret" not in text and "creds:" not in text, "no hardcoded GUID, client secret or creds blob")
confirm = " ".join(s.get("run", "") for s in steps_d if "release-evidence.txt" in s.get("run", ""))
expect("Orders.Api.dll" in confirm and "package_version=${PACKAGE_VERSION}" in confirm, "deploy confirms the downloaded output has Orders.Api.dll and this run's package_version before login")
expect(not any("packages" in s.get("run", "") and "nuget" in s.get("run", "") for s in steps_d), "deploy job pushes no package")
expect("pull_request_target" not in text and "secrets." in text and set(re.findall(r"secrets\.([A-Za-z_]+)", text)) == {"GITHUB_TOKEN"}, "the only secret referenced is the built-in GITHUB_TOKEN (Azure uses variables + OIDC)")
expect(all(not s.get("run", "").count("${{") for s in steps_all), "no ${{ }} expression is interpolated inside a run script (values pass through env)")
checkout = [s for s in steps_b if str(s.get("uses", "")).startswith("actions/checkout")]
expect(len(checkout) == 1 and checkout[0].get("with", {}).get("persist-credentials") is False, "checkout sets persist-credentials: false")
pins = {
    "actions/checkout": "v7",
    "actions/setup-dotnet": "v6",
    "actions/upload-artifact": "v7",
    "actions/download-artifact": "v8",
    "azure/login": "v3",
    "azure/webapps-deploy": "v3",
}
used = {}
sha_ok = True
for line in text.splitlines():
    m = re.match(r"^\s*(?:- )?uses:\s*(\S+)(.*)$", line)
    if m:
        ref, rest = m.groups()
        name, _, pin = ref.partition("@")
        sha_ok &= bool(re.fullmatch(r"[0-9a-f]{40}", pin)) and bool(re.match(r"\s+# v\d+\.\d+\.\d+\s*$", rest))
        used[name] = re.sub(r"^\s+# (v\d+)\..*$", r"\1", rest)
expect(sha_ok, "every action is pinned to a 40-character commit SHA with a trailing `# vX.Y.Z` tag comment")
expect(used == pins, "actions are exactly checkout, setup-dotnet, upload-artifact, download-artifact, azure/login, azure/webapps-deploy at majors v7, v6, v7, v8, v3, v3 (tags resolved 2026-10-30)")
expect(all(isinstance(j.get("timeout-minutes"), int) and 0 < j["timeout-minutes"] <= 30 for j in jobs.values()), "every job sets timeout-minutes (<= 30)")
sdk = [s["with"]["dotnet-version"] for s in steps_b + steps_p if str(s.get("uses", "")).startswith("actions/setup-dotnet")]
expect(sdk and all(str(v) == "10.0.403" for v in sdk), "every setup-dotnet pins 10.0.403 (matches global.json)")
version = next((s.get("run", "") for s in steps_b if s.get("id") == "version"), "")
expect("GITHUB_RUN_NUMBER" in version and "GITHUB_RUN_ATTEMPT" in version, "package version uses run_number and run_attempt (unique on re-run)")
build_step = next((s for s in steps_b if s.get("run") == "bash ci/build.sh"), {})
env = build_step.get("env", {})
expect({"PACKAGE_VERSION", "RUN_ID", "SOURCE_REVISION"} <= set(env), "build step passes PACKAGE_VERSION, RUN_ID and SOURCE_REVISION to ci/build.sh")
expect("github.run_attempt" in str(env.get("RUN_ID")), "RUN_ID carries run_id-run_attempt")
ups = {s["with"]["name"]: s["with"] for s in steps_b if str(s.get("uses", "")).startswith("actions/upload-artifact")}
expect(ups.get("orders-api-web", {}).get("path") == "out/web" and ups.get("orders-api-contracts", {}).get("path") == "out/packages", "uploads out/web and out/packages (paths written by ci/build.sh)")
expect(all(u.get("if-no-files-found") == "error" for u in ups.values()), "uploads fail if no files are found")
push = " ".join(s.get("run", "") for s in steps_p if "nuget push" in s.get("run", ""))
expect("--skip-duplicate" not in push and "nuget.pkg.github.com" in push, "push targets nuget.pkg.github.com and never uses --skip-duplicate")
expect('--api-key "${NUGET_API_KEY}"' in push and "secrets" not in push, "token reaches dotnet through an env variable, not inline")

if failures:
    print(f"{len(failures)} check(s) failed")
    sys.exit(1)
print("ALL WORKFLOW STRUCTURE CHECKS PASSED (file-only; GitHub has not parsed it)")
