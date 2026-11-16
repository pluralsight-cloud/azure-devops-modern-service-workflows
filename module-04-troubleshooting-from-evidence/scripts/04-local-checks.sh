#!/usr/bin/env bash
# Local checks for Module 4 (no accounts, no GitHub, no Azure, nothing pushed to a real
# feed, canonical sample never modified). Reuses the Module 1 orders-api; no second app.
#   bash scripts/04-local-checks.sh
# Needs .NET SDK 10.0.403 (global.json pin), Python 3.9+ with PyYAML, nuget.org for restore.
# Everything runs in a mktemp directory. The only network listener is a MOCK feed bound
# to 127.0.0.1 on a free port, stopped on exit. Mock responses show how `dotnet nuget push`
# reports each HTTP class; they are NOT the wording of Azure Artifacts or GitHub Packages.
set -euo pipefail
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
m1="$here/../module-01-setting-up-traceable-delivery"
wf="$here/workflows/orders-api-github.yml"
work="$(mktemp -d)"
mock_pid=""
cleanup() { if [[ -n "$mock_pid" ]]; then kill "$mock_pid" 2>/dev/null || true; fi; rm -rf "$work"; }
trap cleanup EXIT

fresh_copy() { # $1 = name of the throwaway copy
  rm -rf "$work/$1"; cp -R "$m1/orders-api" "$work/$1"
  rm -rf "$work/$1/out" "$work/$1/src/"*/{bin,obj} "$work/$1/tests/"*/{bin,obj}
}
# Values GitHub would supply for one run; attempt changes, run_number does not.
gh_build() { # $1 copy, $2 attempt, $3 log
  RepositoryUrl="https://github.com/globomantics/orders-api" \
  PACKAGE_VERSION="1.0.${RUN_NUMBER}-attempt.$2" RUN_ID="${RUN_ID_GH}-$2" SOURCE_REVISION="$REV" \
    bash "$work/$1/ci/build.sh" > "$3" 2>&1
}
RUN_NUMBER=12; RUN_ID_GH=9876543210; REV=0123456789abcdef0123456789abcdef01234567

echo "== M4-1. Static: the comparison workflow structure =="
python3 "$here/scripts/check-workflow.py" "$wf" > "$work/wf.log"
tail -n 3 "$work/wf.log"
echo "M4-1 ok: manual dispatch; contents: read; packages: write only on publish-package; id-token: write only on opt-in deploy-staging (environment staging, owner variables, no stored Azure credential); actions pinned"

echo "== M4-2. YAML error vs structure failure vs corrected workflow =="
python3 - "$wf" "$work" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text(); out = pathlib.Path(sys.argv[2])
# (a) YAML error: a tab-indented line cannot be parsed at all.
(out / "bad-yaml.yml").write_text(src.replace("    permissions:\n      contents: read\n      packages: write\n", "    permissions:\n\tcontents: read\n      packages: write\n"))
# (b) valid YAML, wrong structure: publish job lost packages: write.
(out / "no-packages.yml").write_text(src.replace("      packages: write\n", ""))
# (c) valid YAML, over-broad structure: packages: write granted to the whole workflow.
(out / "wide.yml").write_text(src.replace("permissions:\n  contents: read\n\njobs:", "permissions:\n  contents: read\n  packages: write\n\njobs:"))
# (d) valid YAML, wrong version rule: re-runs would repeat the version.
(out / "no-attempt.yml").write_text(src.replace("-attempt.${GITHUB_RUN_ATTEMPT}", ""))
# (e) over-broad: id-token: write granted to the whole workflow instead of only deploy-staging.
(out / "wide-oidc.yml").write_text(src.replace("permissions:\n  contents: read\n\njobs:", "permissions:\n  contents: read\n  id-token: write\n\njobs:"))
# (f) a deployment could be cancelled mid-flight.
(out / "cancel.yml").write_text(src.replace("cancel-in-progress: false", "cancel-in-progress: true"))
# (g) a failed-or-skipped package job would no longer be distinguished: skipped is not accepted.
(out / "no-skip.yml").write_text(src.replace(" || needs.publish-package.result == 'skipped'", ""))
# (h) a literal client ID instead of the owner variable.
(out / "literal-id.yml").write_text(src.replace("client-id: ${{ vars.AZURE_CLIENT_ID }}", "client-id: 11111111-2222-3333-4444-555555555555"))
# (i) the Azure ID moved into a secret reference.
(out / "secret-id.yml").write_text(src.replace("client-id: ${{ vars.AZURE_CLIENT_ID }}", "client-id: ${{ secrets.AZURE_CLIENT_ID }}"))
# (j) deployment no longer needs the opt-in input.
(out / "no-optin.yml").write_text(src.replace("inputs.deployStaging && ", ""))
# (k) deploys a different folder than the one downloaded.
(out / "wrong-path.yml").write_text(src.replace("        package: ${{ runner.temp }}/orders-api-web", "        package: ${{ runner.temp }}/orders-api"))
# (l) a movable tag instead of a full commit SHA.
import re
(out / "tag-pin.yml").write_text(re.sub(r"(uses: actions/checkout)@[0-9a-f]{40} # v7\.0\.1", r"\1@v7", src))
# (m) a job without a timeout.
(out / "no-timeout.yml").write_text(src.replace("    timeout-minutes: 10\n", "", 1))
PY
for f in bad-yaml no-packages wide no-attempt wide-oidc cancel no-skip literal-id secret-id no-optin wrong-path tag-pin no-timeout; do
  set +e; python3 "$here/scripts/check-workflow.py" "$work/$f.yml" > "$work/$f.log" 2>&1; code=$?; set -e
  echo "-- $f.yml: exit $code"; grep -E '^(YAML ERROR|FAIL)' "$work/$f.log" | cut -c1-150
  case "$f" in bad-yaml) test "$code" -eq 2;; *) test "$code" -eq 1;; esac
done
python3 "$here/scripts/check-workflow.py" "$wf" | tail -n 1
echo "M4-2 ok: YAML error exits 2 (cannot parse); twelve structural/safety mutations (permissions, version, deploy gating, cancel, literal/secret Azure ID, path, movable tag pin, missing timeout) exit 1 and name the rule; the corrected file exits 0"

echo "== M4-3. Build as a GitHub run would: attempt 1 then re-run attempt 2 (same run_number) =="
for attempt in 1 2; do
  fresh_copy "app$attempt"
  gh_build "app$attempt" "$attempt" "$work/build$attempt.log"
  grep -q '^PASS: deployable output and contracts package prepared$' "$work/build$attempt.log"
  ls "$work/app$attempt/out/packages"
  echo "--- out/web/release-evidence.txt (attempt $attempt) ---"; cat "$work/app$attempt/out/web/release-evidence.txt"
  ver="1.0.${RUN_NUMBER}-attempt.$attempt"
  test -f "$work/app$attempt/out/packages/Globomantics.Orders.Contracts.$ver.nupkg"
  test -f "$work/app$attempt/out/web/Orders.Api.dll"
  printf 'workload=orders-api\nrun_id=%s-%s\nsource_revision=%s\npackage_version=%s\n' "$RUN_ID_GH" "$attempt" "$REV" "$ver" > "$work/expect$attempt"
  cmp "$work/app$attempt/out/web/release-evidence.txt" "$work/expect$attempt"
  python3 - "$work/app$attempt/out/packages/Globomantics.Orders.Contracts.$ver.nupkg" <<'PY'
import re, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
nuspec = z.read([n for n in z.namelist() if n.endswith(".nuspec")][0]).decode("utf-8-sig")
version = re.search(r"<version>([^<]+)</version>", nuspec).group(1)
assert re.fullmatch(r"\d+\.\d+\.\d+-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*", version), version
repo = re.search(r'<repository type="git" url="([^"]+)"', nuspec).group(1)
assert repo == "https://github.com/globomantics/orders-api", repo
print("nuspec: version=%s repository=%s" % (version, repo))
PY
done
test "$(ls "$work/app1/out/packages")" != "$(ls "$work/app2/out/packages")"
echo "M4-3 ok: attempts 1 and 2 build different package versions from the same run_number; the evidence file, nupkg name and nuspec agree; RepositoryUrl env links the package to the repo without editing the csproj"

echo "== M4-4. Build failure vs check failure, each with its corrected run =="
fresh_copy compiler
printf '\ninternal static class Broken { public static int X = "not a number"; }\n' >> "$work/compiler/src/Orders.Contracts/OrderRules.cs"
set +e; bash "$work/compiler/ci/build.sh" > "$work/compiler.log" 2>&1; code=$?; set -e
test "$code" -ne 0
echo "-- compiler error: exit $code"; grep -m1 'error CS' "$work/compiler.log" | sed -E 's/^.*(error CS[0-9]+: [^[]*).*$/\1/' | cut -c1-140
! grep -q '^PASS:' "$work/compiler.log"
echo "   (no PASS line, no tests ran, no package)"
test ! -e "$work/compiler/out/packages/Globomantics.Orders.Contracts.1.0.0-local.nupkg"
fresh_copy check
python3 - "$work/check/tests/Orders.Checks/Program.cs" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
assert 'order.Status != "ready"' in t
p.write_text(t.replace('order.Status != "ready"', 'order.Status != "shipped"'))
PY
set +e; bash "$work/check/ci/build.sh" > "$work/check.log" 2>&1; code=$?; set -e
test "$code" -ne 0
echo "-- check failure: exit $code"; grep -m1 '^FAIL:' "$work/check.log"
! grep -q 'error CS' "$work/check.log"
echo "   (compiles cleanly; the failing line is the check's own FAIL, so this is a test result, not a compiler error)"
fresh_copy corrected
bash "$work/corrected/ci/build.sh" > "$work/corrected.log" 2>&1
grep -q '^PASS: positive order and invalid-ID checks$' "$work/corrected.log"
grep -q '^PASS: deployable output and contracts package prepared$' "$work/corrected.log"
echo "-- corrected copy (canonical source): both PASS lines return"
echo "M4-4 ok: compiler error, check failure and corrected run are three distinct signatures"

echo "== M4-5. MOCK feed: authentication vs permission vs duplicate version =="
pkg="$(ls "$work/app1/out/packages/"*.nupkg)"
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
push_mock() { # $1 = status the mock returns, $2 = nupkg, $3 = log
  python3 "$here/scripts/mock-feed.py" "$1" "$port" & mock_pid=$!
  sleep 1
  set +e
  dotnet nuget push "$2" --source "http://127.0.0.1:$port/index.json" --api-key MOCK --allow-insecure-connections > "$3" 2>&1; code=$?
  set -e
  kill "$mock_pid" 2>/dev/null || true; wait "$mock_pid" 2>/dev/null || true; mock_pid=""
}
for status in 401 403 409; do
  push_mock "$status" "$pkg" "$work/push$status.log"
  test "$code" -ne 0
  echo "-- mock $status: exit $code"; grep -E '^(error|To skip)' "$work/push$status.log"
done
grep -q '401 (Unauthorized)' "$work/push401.log"
grep -q '403 (Forbidden)' "$work/push403.log"
grep -q '409 (Conflict)' "$work/push409.log"
grep -q -- '--skip-duplicate' "$work/push409.log"
echo "   (401 = identity not accepted; 403 = identity accepted, not allowed to publish; 409 = version already exists. --skip-duplicate would hide the 409, so the workflow never uses it)"
pkg2="$(ls "$work/app2/out/packages/"*.nupkg)"
push_mock 201 "$pkg2" "$work/push201.log"
test "$code" -eq 0
grep -q 'Your package was pushed.' "$work/push201.log"
echo "-- mock 201 with the attempt-2 package (new version): exit $code, 'Your package was pushed.'"
echo "M4-5 ok: three failure classes read differently; a new version, not a delete, is the duplicate recovery. Mock behavior only: real Azure Artifacts and GitHub Packages wording is unverified"

echo "== M4-6. Deploy path mismatch: download folder vs deploy package input (static) =="
python3 - "$m1/orders-api/azure-pipelines.yml" "$work" <<'PY'
import pathlib, re, sys
src = pathlib.Path(sys.argv[1]).read_text(); work = pathlib.Path(sys.argv[2])
# The Staging stage sits inside a template-expression block, so read the file textually.
artifact = re.search(r"download: current\s+artifact: (\S+)", src).group(1)
package = re.search(r"package: (\S+)", src).group(1)
expected = "$(Pipeline.Workspace)/" + artifact
print("download artifact : " + artifact)
print("deploy package    : " + package)
assert package == expected, "canonical file must match"
bad = src.replace("package: $(Pipeline.Workspace)/orders-api-web", "package: $(Pipeline.Workspace)/orders-api")
(work / "mismatch.yml").write_text(bad)
bad_package = re.search(r"package: (\S+)", bad).group(1)
print("mismatched package: " + bad_package)
assert bad_package != "$(Pipeline.Workspace)/" + re.search(r"download: current\s+artifact: (\S+)", bad).group(1)
print("MISMATCH detected : package folder is not the downloaded artifact folder")
PY
mkdir -p "$work/ws/orders-api-web"; cp "$work/app1/out/web/Orders.Api.dll" "$work/ws/orders-api-web/"
test -f "$work/ws/orders-api-web/Orders.Api.dll"
if [[ -e "$work/ws/orders-api" ]]; then echo "FAIL: unexpected folder"; exit 1; fi
echo "local analogue: <workspace>/orders-api-web/Orders.Api.dll exists; <workspace>/orders-api does not"
echo "M4-6 ok: the canonical file's package input matches its downloaded artifact folder; the one-line mismatch is detectable. The real AzureWebApp@1 error wording is not reproduced locally"

echo "== M4-7. Deploy job's own shell steps, run locally (no login, no deploy) =="
python3 - "$wf" "$work" <<'PY'
import pathlib, sys, yaml
doc = yaml.safe_load(pathlib.Path(sys.argv[1]).read_text()); out = pathlib.Path(sys.argv[2])
steps = doc["jobs"]["deploy-staging"]["steps"]
(out / "guard.sh").write_text(steps[0]["run"])
(out / "confirm.sh").write_text(next(s["run"] for s in steps if "release-evidence.txt" in s.get("run", "")))
PY
set +e
env -u AZURE_CLIENT_ID AZURE_TENANT_ID=t AZURE_SUBSCRIPTION_ID=s AZURE_WEBAPP_NAME=a bash "$work/guard.sh" > "$work/guard-missing.log" 2>&1; code=$?
set -e
test "$code" -eq 1
echo "-- guard with AZURE_CLIENT_ID unset: exit $code"; cat "$work/guard-missing.log"
grep -q 'AZURE_CLIENT_ID' "$work/guard-missing.log"
AZURE_CLIENT_ID=c AZURE_TENANT_ID=t AZURE_SUBSCRIPTION_ID=s AZURE_WEBAPP_NAME=a bash "$work/guard.sh" > "$work/guard-ok.log" 2>&1
echo "-- guard with all four set: exit 0"; cat "$work/guard-ok.log"
mkdir -p "$work/rt"; rm -rf "$work/rt/orders-api-web"; cp -R "$work/app1/out/web" "$work/rt/orders-api-web"
RUNNER_TEMP="$work/rt" PACKAGE_VERSION="1.0.${RUN_NUMBER}-attempt.1" bash "$work/confirm.sh" > "$work/confirm-ok.log" 2>&1
echo "-- confirm step, downloaded output matches this run's package_version: exit 0"; tail -n 1 "$work/confirm-ok.log"
set +e
RUNNER_TEMP="$work/rt" PACKAGE_VERSION="1.0.${RUN_NUMBER}-attempt.2" bash "$work/confirm.sh" > "$work/confirm-bad.log" 2>&1; code=$?
set -e
test "$code" -ne 0
echo "-- confirm step, output from a different attempt: exit $code (deployment would stop before login)"
test -f "$work/rt/orders-api-web/Orders.Api.dll"
echo "M4-7 ok: a missing owner variable stops the job before login; the deployed folder is the framework-dependent publish output (Orders.Api.dll + release-evidence.txt) and must carry this run's package_version. Azure login, the environment gate, OIDC trust, the App Service runtime and the deploy itself are NOT exercised"

echo "ALL MODULE 4 LOCAL CHECKS PASSED"
