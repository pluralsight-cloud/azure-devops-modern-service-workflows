#!/usr/bin/env bash
# Local smoke test for the Module 1 sample. Needs only .NET SDK 10.0.403 and network
# access to nuget.org for restore. Runs in a throwaway copy; never touches Azure DevOps,
# never pushes a package, never edits your checkout.
#   bash scripts/01-local-smoke.sh
set -euo pipefail
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
copy() { rm -rf "$work/app"; cp -R "$here/orders-api" "$work/app"; rm -rf "$work/app/out" "$work/app/src/"*/{bin,obj} "$work/app/tests/"*/{bin,obj}; }

echo "== 1. Happy path: bash ci/build.sh with the values the pipeline would pass =="
copy
RUN_ID=999999 SOURCE_REVISION=0123456789abcdef0123456789abcdef01234567 PACKAGE_VERSION=1.0.999999 \
  bash "$work/app/ci/build.sh" | tee "$work/happy.log"
grep -q '^PASS: positive order and invalid-ID checks$' "$work/happy.log"
grep -q '^PASS: deployable output and contracts package prepared$' "$work/happy.log"
test -f "$work/app/out/web/Orders.Api.dll"
test -f "$work/app/out/web/release-evidence.txt"
test -f "$work/app/out/packages/Globomantics.Orders.Contracts.1.0.999999.nupkg"
python3 - "$work/app/out/packages/Globomantics.Orders.Contracts.1.0.999999.nupkg" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as package:
    assert "README.md" in package.namelist()
PY
echo "SMOKE-1 ok: pass lines present; web output, evidence file and local .nupkg exist (nothing pushed)"

echo "== 2. Guard: a second run with stale out/ must stop (exit 2) =="
set +e; bash "$work/app/ci/build.sh" > "$work/guard.log" 2>&1; code=$?; set -e
test "$code" -eq 2 && grep -q '^STOP: out already exists' "$work/guard.log"
echo "SMOKE-2 ok: exit $code with STOP line"

echo "== 3. Negative: break the expectation; the check must fail with exit 1 and no package =="
copy
python3 - "$work/app/tests/Orders.Checks/Program.cs" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
assert 'order.Status != "ready"' in t
p.write_text(t.replace('order.Status != "ready"', 'order.Status != "shipped"'))
PY
set +e; bash "$work/app/ci/build.sh" > "$work/neg.log" 2>&1; code=$?; set -e
grep -q '^FAIL: positive order contract$' "$work/neg.log"
test "$code" -ne 0
test ! -e "$work/app/out/packages/Globomantics.Orders.Contracts.1.0.0-local.nupkg"
test ! -e "$work/app/out/web/Orders.Api.dll"
echo "SMOKE-3 ok: build.sh exit $code, FAIL line present, no publish/pack output"
echo "== 4. Clean-agent simulation: empty NuGet cache and empty CLI home must still build =="
copy
mkdir -p "$work/clean-nuget" "$work/clean-home"
NUGET_PACKAGES="$work/clean-nuget" DOTNET_CLI_HOME="$work/clean-home" \
  RUN_ID=999998 SOURCE_REVISION=0123456789abcdef0123456789abcdef01234567 PACKAGE_VERSION=1.0.999998 \
  bash "$work/app/ci/build.sh" > "$work/clean.log" 2>&1
grep -q '^PASS: deployable output and contracts package prepared$' "$work/clean.log"
grep -qx 'package_version=1.0.999998' "$work/app/out/web/release-evidence.txt"
# The evidence file and the package name carry the same version (build once, publish what was built).
test -f "$work/app/out/packages/Globomantics.Orders.Contracts.1.0.999998.nupkg"
# The sample has no third-party NuGet dependencies, so a cold cache downloads none.
dl="$(find "$work/clean-nuget" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | wc -l | tr -d ' ')"
echo "third-party packages restored into the empty cache: $dl"
test "$dl" -eq 0
echo "SMOKE-4 ok: cold cache builds; evidence version equals package version; no third-party packages restored"
echo "ALL SMOKE CHECKS PASSED"
