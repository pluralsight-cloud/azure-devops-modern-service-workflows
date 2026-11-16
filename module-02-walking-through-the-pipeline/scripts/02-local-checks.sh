#!/usr/bin/env bash
# Local checks for Module 2 (no accounts, no cloud, nothing pushed, nothing in the
# canonical sample modified). Reuses the Module 1 orders-api; there is no second app.
#   bash scripts/02-local-checks.sh
# Needs .NET SDK 10.0.403 (global.json pin), Python 3.9+, PyYAML, nuget.org for restore.
set -euo pipefail
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
m1="$here/../module-01-setting-up-traceable-delivery"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
prep() { bash "$here/scripts/prepare-practice-copy.sh" "$@" > "$work/prep.log"; }

echo "== M2-1. Static: pipeline gates for the build, package and deploy stages =="
python3 "$m1/scripts/check-yaml.py" > "$work/yaml.log"
tail -n 3 "$work/yaml.log"
stage="$m1/orders-api/ci/build-stage.yml"
if grep -q -- '--skip-duplicate' "$stage"; then echo "FAIL: push step passes --skip-duplicate"; exit 1; fi
grep -q 'dotnet nuget push' "$stage"
grep -q 'PACKAGE_VERSION: 1.0.$(Build.BuildId)' "$stage"
echo "M2-1 ok: both options default false, push gated on publishPackages and main, no --skip-duplicate, version is 1.0.\$(Build.BuildId)"

echo "== M2-2. Corrected check (canonical files): pass line, outputs, evidence file =="
prep corrected "$work/corrected"
if grep -q '^diff ' "$work/prep.log"; then echo "FAIL: corrected copy differs from canonical"; exit 1; fi
RUN_ID=111 SOURCE_REVISION=0123456789abcdef0123456789abcdef01234567 PACKAGE_VERSION=1.0.111 \
  bash "$work/corrected/ci/build.sh" > "$work/corrected.log"
grep -q '^PASS: positive order and invalid-ID checks$' "$work/corrected.log"
test -f "$work/corrected/out/web/Orders.Api.dll"
test -f "$work/corrected/out/web/release-evidence.txt"
test -f "$work/corrected/out/packages/Globomantics.Orders.Contracts.1.0.111.nupkg"
grep -q '^package_version=1.0.111$' "$work/corrected/out/web/release-evidence.txt"
echo "M2-2 ok: PASS line; web output, release-evidence.txt and local .nupkg exist (nothing pushed)"

echo "== M2-3. Failing copy: exactly one changed line; check exits 1; nothing published or packed =="
prep failing "$work/failing"
changed="$(diff -r "$m1/orders-api" "$work/failing" -x out -x bin -x obj | grep -c '^[<>]' || true)"
test "$changed" -eq 2   # one line removed, one line added
set +e
RUN_ID=112 SOURCE_REVISION=0123456789abcdef0123456789abcdef01234567 PACKAGE_VERSION=1.0.112 \
  bash "$work/failing/ci/build.sh" > "$work/failing.log" 2>&1; code=$?
set -e
test "$code" -eq 1
grep -q '^FAIL: positive order contract$' "$work/failing.log"
if grep -q '^PASS:' "$work/failing.log"; then echo "FAIL: PASS line in failing run"; exit 1; fi
test ! -e "$work/failing/out/web/Orders.Api.dll"
test ! -e "$work/failing/out/web/release-evidence.txt"
test -z "$(ls -A "$work/failing/out/packages")"
echo "M2-3 ok: build.sh exit $code, FAIL line, out/web and out/packages empty (artifact publish and push would be skipped by their succeeded() gates)"

echo "== M2-4. Duplicate copy: version pinned in exactly the two places; guards reject bad input =="
prep duplicate "$work/duplicate" 4242
grep -q 'PACKAGE_VERSION: 1.0.4242' "$work/duplicate/ci/build-stage.yml"
grep -q 'Globomantics.Orders.Contracts.1.0.4242.nupkg' "$work/duplicate/ci/build-stage.yml"
if grep -E 'PACKAGE_VERSION|\.nupkg' "$work/duplicate/ci/build-stage.yml" | grep -q 'Build.BuildId'; then echo "FAIL: version still derived from Build.BuildId"; exit 1; fi
python3 "$m1/scripts/check-yaml.py" "$work/duplicate" > /dev/null
set +e
bash "$here/scripts/prepare-practice-copy.sh" duplicate "$work/dup2" abc > /dev/null 2>&1; bad=$?
bash "$here/scripts/prepare-practice-copy.sh" failing "$work/failing" > /dev/null 2>&1; occupied=$?
set -e
test "$bad" -eq 64 && test "$occupied" -eq 2
prep corrected "$work/disposable"  # without PRACTICE_FEED_URL: warns, canonical feed
grep -q 'WARNING: PRACTICE_FEED_URL not set' "$work/prep.log"
PRACTICE_FEED_URL=https://pkgs.dev.azure.com/sandbox-org/sandbox-proj/_packaging/practice-feed/nuget/v3/index.json \
  bash "$here/scripts/prepare-practice-copy.sh" duplicate "$work/dispfeed" 4242 > "$work/dispfeed.log"
grep -q '_packaging/practice-feed/' "$work/dispfeed/ci/build-stage.yml"
test "$(grep -o 'https://pkgs\.dev\.azure\.com/[^ "]*/index\.json' "$work/dispfeed/ci/build-stage.yml" | grep -vc '_packaging/practice-feed/')" -eq 0 || { echo "FAIL: real feed URL left in practice copy"; exit 1; }
set +e
PRACTICE_FEED_URL=https://example.com/feed bash "$here/scripts/prepare-practice-copy.sh" failing "$work/badurl" > /dev/null 2>&1; badurl=$?
set -e
test "$badurl" -eq 64
echo "M2-4b ok: PRACTICE_FEED_URL retargets the push away from the real feed; missing value warns; non-Azure-Artifacts URL rejected (64)"
echo "M2-4 ok: pinned version 1.0.4242 only in env and push path; non-numeric ID rejected (64); non-empty target refused (2)"
echo "NOT PROVEN LOCALLY: Azure Artifacts HTTP 409 for a duplicate (a local folder feed overwrites silently)."

echo "== M2-5. Evidence index shape unchanged by Module 2 =="
python3 "$m1/scripts/check-evidence.py" "$m1/../shared/release-evidence.md"
echo "ALL MODULE 2 LOCAL CHECKS PASSED"
