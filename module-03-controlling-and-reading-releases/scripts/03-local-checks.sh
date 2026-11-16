#!/usr/bin/env bash
# Local checks for Module 3 (no accounts, no cloud, nothing pushed or deployed,
# canonical sample never modified). Reuses the Module 1 orders-api; no second app.
#   bash scripts/03-local-checks.sh
# Needs .NET SDK 10.0.403 (global.json pin), Python 3.9+, curl, nuget.org for restore.
# Starts the published app on 127.0.0.1 only, on a free port, and stops it on exit.
set -euo pipefail
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
m1="$here/../module-01-setting-up-traceable-delivery"
work="$(mktemp -d)"
pid=""
cleanup() { if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; fi; rm -rf "$work"; }
trap cleanup EXIT

run_id=4300
rev=0123456789abcdef0123456789abcdef01234567
ver="1.0.$run_id"

echo "== M3-1. Static: the Staging stage definition =="
python3 "$m1/scripts/check-yaml.py" > "$work/yaml.log"
tail -n 2 "$work/yaml.log"
yml="$m1/orders-api/azure-pipelines.yml"
grep -q "eq(parameters.deployStaging, true)" "$yml"
grep -q "eq(variables\['Build.SourceBranch'\], 'refs/heads/main')" "$yml"
grep -q "environment: staging" "$yml"
grep -q "artifact: orders-api-web" "$yml"
grep -Eq "azureSubscription: [A-Za-z0-9._-]+$" "$yml"
grep -Eq "appName: [A-Za-z0-9-]+$" "$yml"
grep -q "appType: webAppLinux" "$yml"
echo "M3-1 ok: Staging needs deployStaging=true and main; deployment job targets environment staging; downloads orders-api-web; AzureWebApp@1 names a service connection and App Service (yours after set-my-names)"

echo "== M3-2. Build a throwaway copy with run $run_id (the build writes release-evidence.txt) =="
cp -R "$m1/orders-api" "$work/orders-api"
rm -rf "$work/orders-api/out" "$work/orders-api/bin" "$work/orders-api/obj"
RUN_ID=$run_id SOURCE_REVISION=$rev PACKAGE_VERSION=$ver bash "$work/orders-api/ci/build.sh" > "$work/build.log"
grep -q '^PASS: deployable output and contracts package prepared$' "$work/build.log"
web="$work/orders-api/out/web"
test -f "$web/Orders.Api.dll"
test -f "$web/release-evidence.txt"
echo "M3-2 ok: web output and release-evidence.txt created; nothing pushed"

echo "== M3-3. Run the web output on 127.0.0.1 and read the three endpoints =="
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
# The app reads release-evidence.txt from its content root, which defaults to the working directory.
(cd "$web" && exec dotnet Orders.Api.dll --urls "http://127.0.0.1:$port" > "$work/app.log" 2>&1) &
pid=$!
ready=no
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if curl -fsS "http://127.0.0.1:$port/health" > "$work/health.out" 2>/dev/null; then ready=yes; break; fi
  sleep 1
done
test "$ready" = yes || { echo "FAIL: app did not answer /health in 15 s"; cat "$work/app.log"; exit 1; }
curl -sS -D "$work/release.hdr" "http://127.0.0.1:$port/release" > "$work/release.out"
curl -sS "http://127.0.0.1:$port/orders/42" > "$work/order.out"
echo "--- GET /release ---";   cat "$work/release.out"
echo "--- GET /health ---";    cat "$work/health.out"; echo
echo "--- GET /orders/42 ---"; cat "$work/order.out"; echo
printf 'workload=orders-api\nrun_id=%s\nsource_revision=%s\npackage_version=%s\n' "$run_id" "$rev" "$ver" > "$work/release.expect"
cmp "$work/release.out" "$work/release.expect"
head -n 1 "$work/release.hdr" | grep -q '200'
grep -qi '^content-type: text/plain' "$work/release.hdr"
test "$(cat "$work/health.out")" = '{"status":"ok"}'
test "$(cat "$work/order.out")" = '{"id":42,"status":"ready"}'
echo "M3-3 ok: /release is plain text with four lines; /health is {\"status\":\"ok\"}; /orders/42 is {\"id\":42,\"status\":\"ready\"}"

echo "== M3-4. /release is 404 when the evidence file is absent =="
rm "$web/release-evidence.txt"
code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/release")"
test "$code" = 404
echo "M3-4 ok: HTTP $code without release-evidence.txt"
kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; pid=""

echo "== M3-5. Section C extra lines: the checker tolerates them and still guards run separation =="
cp "$m1/../shared/release-evidence.md" "$work/ev.md"
python3 - "$work/ev.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
rev = "0123456789abcdef0123456789abcdef01234567"
t = t.replace("- Run ID: pending\n- Revision (full 40-character commit ID): pending\n- Package (",
              "- Run ID: 4300\n- Revision (full 40-character commit ID): " + rev + "\n- Package (")
t = t.replace("- Deployment (`staging` environment history): pending",
              "- Deployment (`staging` environment history): run 4300, example entry\n"
              "- Approval (staging check): example-approver, 2026-01-01T00:00Z\n"
              "- Work item: 128\n"
              "- Runtime (/release): run_id=4300, source_revision=" + rev)
open(p, "w", encoding="utf-8").write(t)
PY
grep -q '^- Approval (staging check): ' "$work/ev.md"
python3 "$m1/scripts/check-evidence.py" "$work/ev.md"
# A duplicated run ID across sections must still fail.
sed 's/^- Run ID: pending$/- Run ID: 4300/' "$work/ev.md" > "$work/ev-dup.md"
if python3 "$m1/scripts/check-evidence.py" "$work/ev-dup.md" > /dev/null; then echo "FAIL: shared run ID accepted"; exit 1; fi
python3 "$m1/scripts/check-evidence.py" "$m1/../shared/release-evidence.md"
echo "M3-5 ok: three extra Section C lines pass the checker; duplicated run IDs still fail; the supplied template is unchanged and passes (example values exist only in a temp file)"
echo "NOT PROVEN LOCALLY: Azure DevOps approval, rejection, timeout, deployment history, App Service runtime, service connection, tenant UI labels."
echo "ALL MODULE 3 LOCAL CHECKS PASSED"
