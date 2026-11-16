#!/usr/bin/env bash
# Prepare a throwaway COPY of the canonical Module 1 orders-api for one Module 2
# practice scenario. Local files only: no git, no network, no Azure DevOps, no push.
# The canonical sample is never modified.
#
#   bash scripts/prepare-practice-copy.sh corrected  <empty-or-new-dir>
#   bash scripts/prepare-practice-copy.sh failing    <empty-or-new-dir>
#   bash scripts/prepare-practice-copy.sh duplicate  <empty-or-new-dir> <already-published-build-id>
#
# Optional, for a disposable practice project: set
#   PRACTICE_FEED_URL=https://pkgs.dev.azure.com/<org>/<project>/_packaging/<feed>/nuget/v3/index.json
# to retarget the push of ANY scenario. The sample YAML holds ONE real feed URL
# (yours after set-my-names.sh), so without it a practice run pushes to that feed.
#
# corrected : canonical files (plus only the feed URL when PRACTICE_FEED_URL is set).
# failing   : canonical + ONE changed assertion (`"ready"` -> `"shipped"`) in
#             tests/Orders.Checks/Program.cs. Same single edit as Module 1's smoke test.
# duplicate : canonical + the version pinned to 1.0.<build-id> in the two places the
#             pipeline derives it (PACKAGE_VERSION env and the push file name), so the
#             push repeats a version the feed already holds. Pipeline queue-time inputs
#             cannot do this: the version comes from $(Build.BuildId) in YAML.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$here/../module-01-setting-up-traceable-delivery/orders-api"
scenario="${1:-}"; dest="${2:-}"; build_id="${3:-}"

usage() { sed -n '2,22p' "${BASH_SOURCE[0]}"; exit 64; }
[[ -d "$src" ]] || { echo "STOP: canonical orders-api not found at $src"; exit 66; }
[[ -n "$scenario" && -n "$dest" ]] || usage
case "$scenario" in corrected|failing|duplicate) ;; *) usage ;; esac
if [[ -e "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
  echo "STOP: $dest exists and is not empty; choose a new directory (nothing was changed)."; exit 2
fi
if [[ "$scenario" == duplicate && ! "$build_id" =~ ^[0-9]+$ ]]; then
  echo "STOP: duplicate needs the numeric Build ID of the run that already pushed the package (read it from the feed page; never guess)."; exit 64
fi

feed_url="${PRACTICE_FEED_URL:-}"
if [[ -n "$feed_url" && ! "$feed_url" =~ ^https://pkgs\.dev\.azure\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/_packaging/[A-Za-z0-9._-]+/nuget/v3/index\.json$ ]]; then
  echo "STOP: PRACTICE_FEED_URL must be a project-scoped https://pkgs.dev.azure.com/<org>/<project>/_packaging/<feed>/nuget/v3/index.json URL."; exit 64
fi

mkdir -p "$dest"
cp -R "$src/." "$dest/"
rm -rf "$dest/out" "$dest"/src/*/bin "$dest"/src/*/obj "$dest"/tests/*/bin "$dest"/tests/*/obj

python3 - "$scenario" "$dest" "$build_id" "$feed_url" <<'PY'
import pathlib, re, sys
scenario, dest, build_id, feed_url = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4]
FEED_PATTERN = r"https://pkgs\.dev\.azure\.com/[^/\s\"]+/[^/\s\"]+/_packaging/[^/\s\"]+/nuget/v3/index\.json"

def replace_once(path, old, new):
    text = path.read_text()
    assert text.count(old) == 1, f"expected exactly one {old!r} in {path}, found {text.count(old)}"
    path.write_text(text.replace(old, new))

if feed_url:
    stage_file = dest / "ci/build-stage.yml"
    text = stage_file.read_text()
    found = re.findall(FEED_PATTERN, text)
    assert len(found) == 1, f"expected exactly one feed URL in {stage_file}, found {len(found)}"
    replace_once(stage_file, found[0], feed_url)

if scenario == "failing":
    replace_once(dest / "tests/Orders.Checks/Program.cs", 'order.Status != "ready"', 'order.Status != "shipped"')
elif scenario == "duplicate":
    stage = dest / "ci/build-stage.yml"
    replace_once(stage, "PACKAGE_VERSION: 1.0.$(Build.BuildId)", f"PACKAGE_VERSION: 1.0.{build_id}")
    replace_once(stage, "Globomantics.Orders.Contracts.1.0.$(Build.BuildId).nupkg",
                 f"Globomantics.Orders.Contracts.1.0.{build_id}.nupkg")
PY

echo "Prepared '$scenario' copy in: $dest"
if [[ -z "$feed_url" ]]; then
  echo "WARNING: PRACTICE_FEED_URL not set; a practice run of this copy pushes to the real feed in ci/build-stage.yml."
fi
echo "Difference from the canonical sample (empty for corrected):"
diff -ru "$src" "$dest" -x out -x bin -x obj || true
